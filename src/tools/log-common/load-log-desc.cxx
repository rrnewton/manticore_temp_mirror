/* load-log-desc.cxx
 *
 * COPYRIGHT (c) 2009 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 */

#include <assert.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdarg.h>
#include "event-desc.hxx"
#include "log-desc.hxx"
#include "json.h"

/* NOTE: this table should agree with the "alignAndSize" function in
 * src/gen/log-gen/event-sig.sml.
 */
static struct {
    int		szb;	// size of argument in bytes
    int		alignb;	// alignment restriction in bytes
}	ArgTyInfo[] = {
	{ 8, 8 },	// ADDR
	{ 4, 4 },	// INT
	{ 4, 4 },	// WORD
	{ 4, 4 },	// FLOAT
	{ 8, 8 },	// DOUBLE
	{ 8, 8 },	// NEW_ID
	{ 8, 8 },	// EVENT_ID
	/* no entries for STR0, ... */
    };

class LogFileDescLoader {
  public:
    LogFileDescLoader ()
    {
	this->_desc = 0;
	this->_nextId = 1;  // 0 is reserved for NoEvent
    }

    LogFileDesc *FileDesc () const { return this->_desc; }

    bool GetLogEventsFile (JSON_Value_t *v);
    bool GetLogViewFile (JSON_Value_t *v);

    EventDesc *NewEvent (JSON_Value_t *v);
    Group *NewGroup (JSON_Value_t *obj);

    EventDesc *GetEventByName (JSON_Value_t *v);
    EventDesc *GetEventField (JSON_Value_t *v, const char *name);

    void Error (const char *fmt, ...);

  protected:
    LogFileDesc		*_desc;
    int			_nextId;

    ArgDesc *_GetArgs (JSON_Value_t *v);

};

inline char *CopyString (const char *s)
{
    if (s == 0) return 0;
    return strcpy (new char[strlen(s)+1], s);
}

/*! \brief process the "args" array of an event descriptor.
 *  \param v the JSON object that represents the array of argument descriptors.
 *  \return the argument descriptors.
 */
ArgDesc *LogFileDescLoader::_GetArgs (JSON_Value_t *v)
{
    unsigned int location = 12;  /* the argument area starts at byte 12 */
    unsigned int nextLoc;

    assert ((v->tag == JSON_array) || (v->u.array.length > 0));

    ArgDesc *ads = new ArgDesc[v->u.array.length];

    for (int i = 0;  i < v->u.array.length;  i++) {
	JSON_Value_t *arg = JSON_GetElem(v, i);

      /* get the fields */
	const char *name = JSON_GetString(JSON_GetField(arg, "name"));
	const char *tyStr = JSON_GetString(JSON_GetField(arg, "ty"));
	JSON_Value_t *loc = JSON_GetField(arg, "loc");
	const char *desc = JSON_GetString(JSON_GetField(arg, "desc"));
	if ((name == 0) || (tyStr == 0) || (desc == 0)) {
	    delete[] ads;
	    this->Error ("badly formed argument\n");
	    return 0;
	}

      /* translate the argument type */
	ArgType ty;
	int n;
	if (strcasecmp(tyStr, "addr") == 0) ty = ADDR;
	else if (strcasecmp(tyStr, "int") == 0) ty = INT;
	else if (strcasecmp(tyStr, "word") == 0) ty = WORD;
	else if (strcasecmp(tyStr, "float") == 0) ty = FLOAT;
	else if (strcasecmp(tyStr, "double") == 0) ty = DOUBLE;
	else if (strcasecmp(tyStr, "new-id") == 0) ty = NEW_ID;
	else if (strcasecmp(tyStr, "id") == 0) ty = EVENT_ID;
	else if (sscanf(tyStr, "str%d", &n) == 1) ty = (ArgType)((int)STR0 + n);
	else {
	    delete[] ads;
	    this->Error ("unrecognized argument type \"%s\" for field \"%s\"\n",
		tyStr, name);
	    return 0;
	}

      /* compute the location (if not given) */
	int sz, align;
	if (ty >= STR0) {
	    sz = ty - STR0;
	    align = 1;
	}
	else {
	    sz = ArgTyInfo[ty].szb;
	    align = ArgTyInfo[ty].szb;
	}
	if (loc != 0) {
	    if (loc->tag != JSON_int) {
		delete[] ads;
		this->Error ("expected integer for \"loc\" field\n");
		return 0;
	    }
	    location = loc->u.integer;
	}
	else {
	    location = (location + (align-1)) & ~(align-1);
	}
	nextLoc = location + sz;

	ads[i].name = CopyString(name);
	ads[i].ty = ty;
	ads[i].loc = location;
	ads[i].desc = CopyString(desc);

	location = nextLoc;
    }

    return ads;
}

/*! \brief construct a log-file description by reading in the JSON file.
 *  \param logDescFile the path to the log-events.json file
 *  \param logViewFile the path to the log-view.json file
 *  \return the log-file descriptor or 0 if there was an error.
 */
LogFileDesc *LoadLogDesc (const char *logDescFile, const char *logViewFile)
{
    LogFileDescLoader loader;
    JSON_Value_t *jVal = JSON_ParseFile (logDescFile);
    bool r1 = loader.GetLogEventsFile (jVal);
    if (r1
    && loader.GetLogViewFile (JSON_ParseFile (logViewFile)))
	return loader.FileDesc();
    else
	return 0;

}


/***** class LogFileDescLoader member functions *****/

bool LogFileDescLoader::GetLogEventsFile (JSON_Value_t *v)
{
    if (v == 0) return false;

    const char *date = JSON_GetString(JSON_GetField(v, "date"));
    JSON_Value_t *version = JSON_GetField(v, "version");

    JSON_Value_t *events = JSON_GetField(v, "events");

    if ((events == 0) || events->tag != JSON_array) return 0;

  // allocate the events vector, including a slot for NoEvent
    std::vector<EventDesc *> *eds =
	new std::vector<EventDesc *> (events->u.array.length + 1, (EventDesc *)0);
    this->_desc = new LogFileDesc (eds);

  /* initialize the events array */
    eds->at(0) = new EventDesc ();  /* NoEvent */
    for (unsigned int i = 1;  i < eds->size();  i++) {
	EventDesc *ed = NewEvent (events->u.array.elems[i-1]);
	if (ed == 0) return false;
	eds->at(i) = ed;
    }

    return true;

}

bool LogFileDescLoader::GetLogViewFile (JSON_Value_t *v)
{
    if ((v == 0) || (this->_desc == 0)) return false;

    const char *date = JSON_GetString(JSON_GetField(v, "date"));
    JSON_Value_t *version = JSON_GetField(v, "version");
    JSON_Value_t *root = JSON_GetField(v, "root");

/* FIXME: we should check consistency between the log-events file
 * and the log-view file.
 */

    if ((date == 0) || (version == 0) || (root == 0)
    || (root->tag != JSON_object))
	return false;

    Group *grp = this->NewGroup (root);
    if ((grp == 0) || (grp->Kind() != EVENT_GROUP))
	return false;
    this->_desc->_root = dynamic_cast<EventGroup *>(grp);

    assert (this->_desc->_root != 0);

  // finish up by computing the per-event info
    this->_desc->_InitEventInfo ();

    return true;

}

EventDesc *LogFileDescLoader::NewEvent (JSON_Value_t *v)
{
    const char *name = JSON_GetString(JSON_GetField(v, "name"));
    JSON_Value_t *args = JSON_GetField(v, "args");
    const char *desc = JSON_GetString(JSON_GetField(v, "desc"));

    if ((name == 0) || (args == 0) || (desc == 0) || (args->tag != JSON_array))
	return 0;

    ArgDesc *ads;
    if (args->u.array.length == 0)
	ads = 0;
    else if ((ads = this->_GetArgs(args)) == 0) {
	this->Error("bad argument for event %s\n", name);
	return 0;
    }

  /* get optional "attrs" field */
    JSON_Value_t *attrs = JSON_GetField (args, "attrs");
    EventAttrs_t attributes = ATTR_NONE;
    if (attrs != 0) {
	if (attrs->tag != JSON_array) {
	    delete ads;
	    return 0;
	}
	for (int i = 0;  i < attrs->u.array.length;  i++) {
	    const char *attr = JSON_GetString(attrs->u.array.elems[i]);
	    if (attr == 0)
		return 0;
	    else if (strcasecmp(attr, "src") == 0)
		attributes |= (ATTR_SRC | ATTR_DEPENDENT);
	    else if (strcasecmp(attr, "pml") == 0)
		attributes |= ATTR_PML;
	    else if (strcasecmp(attr, "rt") == 0)
		attributes |= ATTR_RT;
	    else
		return 0;
	}
    }

    EventDesc *ed = new EventDesc (
	    name, this->_nextId++, attributes,
	    args->u.array.length, ads,
	    CopyString(desc));

    return ed;

}

Group *LogFileDescLoader::NewGroup (JSON_Value_t *v)
{
    const char *desc = JSON_GetString(JSON_GetField(v, "desc"));
    const char *kindStr = JSON_GetString(JSON_GetField(v, "kind"));

    if ((desc == 0) || (kindStr == 0)) return 0;

    if (strcasecmp(kindStr, "group") == 0) {
	JSON_Value_t *events = JSON_GetField(v, "events");
	JSON_Value_t *groups = JSON_GetField(v, "groups");
	if ((events == 0) || (events->tag != JSON_array)
	|| (groups == 0) || (groups->tag != JSON_array))
	    return 0;
	EventGroup *grp =
	    new EventGroup (desc,
		events->u.array.length, groups->u.array.length);
      /* add events to the group */
	for (int i = 0;  i < events->u.array.length;  i++) {
	    EventDesc *evt = this->GetEventByName (events->u.array.elems[i]);
	    if (evt == 0)
		return 0;
	    grp->AddEvent (i, evt);
	}
      /* add sub-groups to the group */
	for (int i = 0;  i < groups->u.array.length;  i++) {
	    JSON_Value_t *g = groups->u.array.elems[i];
	    if ((g == 0) || (g->tag != JSON_object))
		return 0;
	    Group *subgrp = this->NewGroup(g);
	    if (subgrp == 0)
		return 0;
	    grp->AddGroup (i, subgrp);
	}
	return grp;
    }
    else if (strcasecmp(kindStr, "state") == 0) {
	const char *start = JSON_GetString(JSON_GetField(v, "start"));
	JSON_Value_t *states = JSON_GetField(v, "states");
	JSON_Value_t *colors = JSON_GetField(v, "colors");
	JSON_Value_t *trans = JSON_GetField(v, "transitions");
	if ((start == 0)
	|| (states == 0) || (states->tag != JSON_array)
	|| (trans == 0) || (trans->tag != JSON_array))
	    return 0;
	int nStates = states->u.array.length;
	if ((colors != 0)
	&& ((colors->tag != JSON_array) || (colors->u.array.length != nStates)))
	    return 0;
	int nColors = (colors == 0) ? 0 : colors->u.array.length;
	int nTrans = trans->u.array.length;
	if ((nStates == 0) || (nTrans == 0)) return 0;
	StateGroup *grp = new StateGroup (desc, nStates, nTrans);
      /* add the state names */
	for (int i = 0;  i < nStates;  i++) {
	    grp->AddState(i,
		JSON_GetString(states->u.array.elems[i]),
		(colors == 0) ? 0 : JSON_GetString(colors->u.array.elems[i]));
	}
      /* add the transitions */
	for (int i = 0;  i < nTrans;  i++) {
	  /* add transitions and mark events as being in a state group */
	    JSON_Value_t *t = trans->u.array.elems[i];
	    if ((t == 0) || (t->tag != JSON_array) || (t->u.array.length != 2))
		return 0;
	    EventDesc *evt = this->GetEventByName (t->u.array.elems[0]);
	    const char *stName = JSON_GetString(t->u.array.elems[1]);
	    if ((evt == 0) || (stName == 0))
		return 0;
	    grp->AddTransition (i, evt, stName);
	    evt->SetAttr (ATTR_STATE);
	}
      /* record the start state */
	grp->SetStart (start);
	return grp;
    }
    else if (strcasecmp(kindStr, "interval") == 0) {
	EventDesc *a = this->GetEventField (v, "start");
	EventDesc *b = this->GetEventField (v, "end");
	const char *color = JSON_GetString(JSON_GetField(v, "color"));
	if ((a == 0) || (b == 0))
	    return 0;
	else {
	    a->SetAttr (ATTR_INTERVAL);
	    b->SetAttr (ATTR_INTERVAL);
	    return new IntervalGroup (desc, a, b, color);
	}
    }
    else if (strcasecmp(kindStr, "dependent") == 0) {
	EventDesc *src = this->GetEventField (v, "src");
	EventDesc *dst = this->GetEventField (v, "dst");
	const char *color = JSON_GetString(JSON_GetField(v, "color"));
	if ((src == 0) || (dst == 0))
	    return 0;
	else {
	    src->SetAttr (ATTR_DEPENDENT);
	    dst->SetAttr (ATTR_DEPENDENT);
	    return new DependentGroup (desc, src, dst, color);
	}
    }
    else {
	this->Error("bad group kind %s\n", kindStr);
	return 0;
    }

}

EventDesc *LogFileDescLoader::GetEventByName (JSON_Value_t *v)
{
    const char *evtName = JSON_GetString(v);
    if (evtName == 0)
	return 0;
    EventDesc *ed = this->_desc->FindEventByName (evtName);
    if (ed == 0)
	this->Error ("unknown event \"%s\"\n", evtName);
    return ed;

}

EventDesc *LogFileDescLoader::GetEventField (JSON_Value_t *v, const char *name)
{
    JSON_Value_t *fld = JSON_GetField(v, name);

    if (fld == 0) {
	this->Error ("unable to find field \"%s\" in JSON object\n", name);
	return 0;
    }
    else
	return this->GetEventByName (fld);

}

/* error reporting */
void LogFileDescLoader::Error (const char *fmt, ...)
{
    va_list va;
    va_start (va, fmt);
    vfprintf (stderr, fmt, va);
    va_end (va);
}
