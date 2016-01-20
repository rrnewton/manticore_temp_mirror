/* basis.c
 *
 * COPYRIGHT (c) 2007 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 */

#include "manticore-rt.h"
#include <stdio.h>
#include <string.h>
#include <sys/time.h>
#include <math.h>
#include <ctype.h>
#include <inttypes.h>
#include "vproc.h"
#include "topology.h"
#include "value.h"
#include "heap.h"
#include "options.h"

/* is a string in hex format? */
STATIC_INLINE bool isHex (const char *s, int len)
{
    return ((len >= 3) && (s[0] == '0') && ((s[1] == 'x') || (s[1] == 'X')));
}

/* M_Arguments : unit -> string list
 */
Value_t M_Arguments ()
{
    int nArgs = NumOptions();
    if (nArgs > 0) {
	const char **args = Options();
	VProc_t *vp = VProcSelf();
	Value_t l = M_NIL;
	for (int i = nArgs-1;  i >= 0;  i--) {
	    l = Cons(vp, AllocString(vp, args[i]), l);
	}
	return l;
    }
    else
	return M_NIL;

}

/* M_IntToString:
 */
Value_t M_IntToString (int32_t n)
{
    char buf[32];
    snprintf(buf, sizeof(buf), "%d", n);
    return AllocString (VProcSelf(), buf);
}

/* M_IntFromString : string -> int option
 */
Value_t M_IntFromString (SequenceHdr_t *s)
{
    int len = s->len;
    const char *str = (const char *)(s->data);

  // skip leading white space
    while ((len > 0) && isspace(*str)) {
	len--;
	str++;
    }

    Value_t result = M_NONE;

    if (len > 0) {
	int32_t n;
	if (isHex (str, len)) {
	    if (sscanf(str, "%x", (uint32_t *)&n) != 1)
		return M_NONE;
	}
	else if (sscanf(str, "%d", &n) != 1)
	    return M_NONE;
	VProc_t *vp = VProcSelf();
	return Some(vp, WrapWord(vp, (Word_t)n));
    }
    else
	return M_NONE;

}

/* M_LongToString:
 */
Value_t M_LongToString (int64_t n)
{
    char buf[32];
    snprintf(buf, sizeof(buf), "%" PRIi64, n);
    return AllocString (VProcSelf(), buf);
}

/* M_LongFromString : string -> long option
 */
Value_t M_LongFromString (SequenceHdr_t *s)
{
    int len = s->len;
    const char *str = (const char *)(s->data);

  // skip leading white space
    while ((len > 0) && isspace(*str)) {
	len--;
	str++;
    }

    Value_t result = M_NONE;

    if (len > 0) {
	int64_t n;
	if (isHex (str, len)) {
	    if (sscanf(str, "%" PRIu64, (uint64_t *)&n) != 1)
		return M_NONE;
	}
	else if (sscanf(str, "%" PRIi64, &n) != 1)
	    return M_NONE;
	VProc_t *vp = VProcSelf();
	return Some(vp, WrapWord(vp, (Word_t)n));
    }
    else
	return M_NONE;

}

/* M_Word64ToString:
 */
Value_t M_Word64ToString (uint64_t n)
{
    char buf[32];
    snprintf(buf, sizeof(buf), "%" PRIu64, n);
    return AllocString (VProcSelf(), buf);
}

/* M_FloatToString:
 */
Value_t M_FloatToString (float f)
{
    char buf[64];
    snprintf(buf, sizeof(buf), "%f", (double)f);
    return AllocString (VProcSelf(), buf);
}

/* M_FloatFromString:
 */
Value_t M_FloatFromString (Value_t str)
{
    VProc_t             *vp = VProcSelf ();
    SequenceHdr_t	*strS = (SequenceHdr_t *)ValueToPtr(str);
    if (strS->len < 1) {
	return M_NONE;
    }
    else {
	char *strData = (char*)strS->data;
	if (strData[0] == '~')
	    strData[0] = '-';
	float f;
	int ret = sscanf (strData, "%f", &f);
	RawFloat_t rf;
	rf.f = f;
	if (ret > 0) {
	    return Some (vp, AllocNonUniform(vp, 1, FLOAT(rf)));
	}
	else {
	    return M_NONE;
	}
    }
}

/* M_DoubleToString:
 */
Value_t M_DoubleToString (double f)
{
    char buf[64];
    snprintf(buf, sizeof(buf), "%.10f", f);
    return AllocString (VProcSelf(), buf);
}

Value_t M_DoubleFromString (Value_t str)
{
    VProc_t             *vp = VProcSelf ();
    SequenceHdr_t	*strS = (SequenceHdr_t *)ValueToPtr(str);
    if (strS->len < 1) {
	return M_NONE;
    }
    else {
	char *strData = (char*)strS->data;
	if (strData[0] == '~')
	    strData[0] = '-';
	double d;
	int ret = sscanf (strData, "%lf", &d);
	RawDouble_t rd;
	rd.d = d;
	if (ret > 0) {
	    return Some (vp, AllocNonUniform(vp, 1, DOUBLE(rd)));
	}
	else {
	    return M_NONE;
	}
    }
}

void M_Print_Long(const char * s, uint64_t addr){
    char str [100];
    sprintf(str, "[%d]: %s", VProcSelf()->id, s);
    printf(str, addr);
}

void M_Print_Long_Long(const char *s, uint64_t addr, uint64_t v){
    char str [100];
    sprintf(str, "[%d]: %s", VProcSelf()->id, s);
    printf(str, addr, v);
}

void M_Print_Long_Int(const char *s, uint64_t addr, uint32_t v){
    char str [100];
    sprintf(str, "[%d]: %s", VProcSelf()->id, s);
    printf(str, addr, v);
}

void M_Print_Long_Byte(const char *s, uint64_t addr, uint8_t v){
    char str [100];
    sprintf(str, "[%d]: %s", VProcSelf()->id, s);
    printf(str, addr, v);
}

void M_Print_Long_Short(const char *s, uint64_t addr, uint16_t v){
    char str [100];
    sprintf(str, "[%d]: %s", VProcSelf()->id, s);
    printf(str, addr, v);
}

/* M_Print:
 */
void M_Print (const char *s)
{
#ifdef NDEBUG
    Say("%s", s);
#else
    Say("[%2d] %s", VProcSelf()->id, s);
#endif
}

/* M_PrintOrd:
 */
void M_PrintOrd (const int i)
{
#ifdef NDEBUG
    putchar(i);
#else
    Say("[%2d] %c", VProcSelf()->id, i);
#endif
}

/* M_StringSame
 * returns 1 when the two Manticore strings are the same length and contain the same
 * characters and 0 otherwise
 */
int M_StringSame (Value_t a, Value_t b)
{
    SequenceHdr_t	*s1 = (SequenceHdr_t *)ValueToPtr(a);
    SequenceHdr_t	*s2 = (SequenceHdr_t *)ValueToPtr(b);
    int same = 1;

    if (s1->len != s2->len) { return 0; }
    else {
	char *str1 = (char *)ValueToPtr(s1->data);
	char *str2 = (char *)ValueToPtr(s2->data);
	for (int i = 0; i < s1->len; i++)
	    if (str1[i] != str2[i])
		return 0;
    }
    return same;
}

/* M_StringConcat2:
 */
Value_t M_StringConcat2 (Value_t a, Value_t b)
{
    SequenceHdr_t	*s1 = (SequenceHdr_t *)ValueToPtr(a);
    SequenceHdr_t	*s2 = (SequenceHdr_t *)ValueToPtr(b);

    if (s1->len == 0) return b;
    else if (s2->len == 0) return a;
    else {
	VProc_t *vp = VProcSelf();
	uint32_t len = s1->len + s2->len;
	Value_t data = AllocRaw(vp, len + 1);
      // initialize the data object
	Byte_t *p = (Byte_t *)ValueToPtr(data);
	memcpy (p, ValueToPtr(s1->data), s1->len);
	memcpy (p+s1->len, ValueToPtr(s2->data), s2->len);
	p[len] = 0;
      // allocate the sequence-header object
	return AllocNonUniform(vp, 2, PTR(data), INT((Word_t)len));
    }

}

/* M_StringConcatList:
 * XXX - Could this somehow be defined in the HLOp language?  I'm not
 * familiar enough with it, so I don't know. -JDR
 */
Value_t M_StringConcatList (Value_t l)
{
    VProc_t *vp = VProcSelf();
    uint32_t len = 0;
    Value_t data = M_NIL;
    ListCons_t * list_p = (ListCons_t *)ValueToPtr(l);
    ListCons_t * crnt_p = NULL;
    SequenceHdr_t * crnt_str = NULL;
    Byte_t * buf = NULL;

    crnt_p = list_p;
    while (crnt_p != (ListCons_t *)M_NIL) {
        crnt_str = (SequenceHdr_t *)ValueToPtr(crnt_p->hd);
        /* XXX Do we support/want to support really long strings?  If
           so, overflow detection would be a good thing here. */
        len += crnt_str->len;
        crnt_p = (ListCons_t *)ValueToPtr(crnt_p->tl);
    }

    data = AllocRaw(vp, len + 1);
    buf = (Byte_t *)ValueToPtr(data);

    crnt_p = list_p;
    while (crnt_p != (ListCons_t *)M_NIL) {
        crnt_str = (SequenceHdr_t *)crnt_p->hd;
        memcpy(buf, ValueToPtr(crnt_str->data), crnt_str->len);
        buf += crnt_str->len;
        crnt_p = (ListCons_t *)ValueToPtr(crnt_p->tl);
    }

    *buf = 0;
    return AllocNonUniform(vp, 2, PTR(data), INT((Word_t)len));
}

/* M_GetTimeOfDay:
 */
double M_GetTimeOfDay ()
{
    struct timeval	now;

    gettimeofday (&now, 0);

    return (double)(now.tv_sec) + 0.000001 * (double)(now.tv_usec);

}

Time_t M_GetTime ()
{
    struct timeval t;

#if HAVE_CLOCK_GETTIME
    struct timespec time;
    clock_gettime (CLOCK_REALTIME, &time);
    t.tv_sec = time.tv_sec;
    t.tv_usec = time.tv_nsec / 1000;
#else
    gettimeofday (&t, 0);
#endif

    return 1000000 * t.tv_sec + t.tv_usec;
}

double M_GetCPUTime ()
{
  return ((double)clock ()) / CLOCKS_PER_SEC;
}

/* M_GetNumProcs:
 *
 * Return the number of hardware processors.  On processors with
 * hardware multithreading, this will be the number of threads,
 * otherwise it is the number of cores.
 */
int M_GetNumProcs ()
{
    return NumHWThreads;
}

/* M_GetNumVProcs:
 *
 * Return the number of enabled vprocs.
 */
int M_GetNumVProcs ()
{
    return NumVProcs;
}

/***** functions to support debugging *****/

Value_t M_Test ()
{
    return Some(VProcSelf(), AllocUniform (VProcSelf(), 1, 2));
}

#ifndef NDEBUG
void M_AssertNotLocalPtr (Value_t item)
{
  /* item must be a pointer in the global queue, and thus we can
   * at least be sure that it is not in the local queue
   */
    if (inVPHeap ((Addr_t)VProcSelf(), (Addr_t)item)) {
	Die ("Pointer %p is in the local heap when it should be in the global heap\n",
	    (void *)item);
    }

}
#endif

Value_t M_Die (const char *message)
{
    Die ("%s\n", message);
}

Value_t M_AssertFail (const char *check, char *file, int line)
{
    if ((check != (const char *)M_NIL) && (file != (const char *)M_NIL))
	Die ("Assert failed at %s:%d (%s).\n", file, line, check);
    else
	Die ("Assert failed with corrupted diagnostic information.\n");
}

void M_PrintDebug (const char *s)
{
#ifndef NDEBUG
    if (DebugFlg)
	SayDebug("[%2d] %s", VProcSelf()->id, s);
#endif
}

void M_PrintDebugMsg (Value_t alwaysPrint, const char *msg, char *file, int line)
{
#ifndef NDEBUG
    if (DebugFlg || (alwaysPrint==M_TRUE))
	SayDebug ("[%2d] \"%s\" at %s:%d\n", VProcSelf()->id, msg, file, line);
#endif
}

void M_PrintTestingMsg (const char *msg, char *file, int line)
{
    Say ("[%2d] Test failed: \"%s\" at %s:%d\n", VProcSelf()->id, msg, file, line);
}

void M_PrintPtr (const char *name, void *ptr)
{
    Say("[%2d] &%s=%p\n", VProcSelf()->id, name, ptr);
}

/* M_PrintLong:
 */
void M_PrintLong (int64_t n)
{
    Say("%"PRIi64, n);
}

/* M_PrintInt:
 */
void M_PrintInt (int32_t n)
{
    Say("%d\t", n);
}

void M_PrintFloat (float f)
{
    Say ("%f\n",(double)f);
}

int M_ReadInt ()
{
    int i;
    int ignored = scanf ("%d\n", &i);
    return i;
}

float M_ReadFloat ()
{
    float i;
    int ignored = scanf ("%f", &i);
    return (float)i;
}

double M_ReadDouble ()
{
    double i;
    int ignored = scanf ("%lf", &i);
    return i;
}

double M_DRand (double lo, double hi)
{
    return (((double)rand() / ((double)(RAND_MAX)+(double)(1)) ) * (hi-lo)) + lo;
}

float M_FRand (float lo, float hi)
{
    return (((float)rand() / ((float)(RAND_MAX)+(float)(1)) ) * (hi-lo)) + lo;
}

Word_t M_Random (Word_t lo, Word_t hi)
{
    return (random() % (hi - lo)) + lo;
}

int32_t M_RandomInt (int32_t lo, int32_t hi)
{
    return (int)M_Random((int)lo, (int)hi);
}

void M_SeedRand ()
{
    srand(time(NULL));
}

/*! \brief allocate an array in the global heap
 *  \param vp the host vproc
 *  \param nElems the size of the array
 *  \param elt the initial value for the array elements
 */
Value_t M_NewArray (VProc_t *vp, int nElems, Value_t elt)
{
  Say("M_NewArray: fail\n");
  return 0;
}

double M_log (double d)
{
    return log(d);
}

float M_Powf (float x, float y)
{
    return powf(x, y);
}

float M_Cosf (float x)
{
    return cosf(x);
}

float M_Sinf (float x)
{
  return sinf(x);
}

float M_Tanf (float x)
{
  return tanf(x);
}

double M_Pow (double x, double y)
{
  return pow(x, y);
}

double M_Cos (double x)
{
  return cos(x);
}

double M_Sin (double x)
{
  return sin(x);
}

double M_Tan (double x)
{
  return tan(x);
}

double M_Atan (double x)
{
  return atan(x);
}

double M_Atan2 (double x, double y)
{
  return atan2(x,y);
}

int64_t M_Lround (double x)
{
  return lround(x);
}

/*! \brief compute floor(log_2(v)). NOTE: this function relies on little endianness
 */
int M_FloorLg (int v)
{
  int r; // result of log_2(v) goes here
  union { unsigned int u[2]; double d; } t; // temp

  t.u[1] = 0x43300000;
  t.u[0] = v;
  t.d -= 4503599627370496.0;
  r = (t.u[1] >> 20) - 0x3FF;
  return r;
}

/*! \brief compute ceiling(log_2(v))
 */
int M_CeilingLg (int v)
{
  int lg = M_FloorLg(v);
  return lg + (v - (1<<lg) > 0);
}

void *M_TextIOOpenIn (Value_t filename)
{
    SequenceHdr_t	*filenameS = (SequenceHdr_t *)ValueToPtr(filename);

    return fopen ((char*)(filenameS->data), "r");
}

void M_TextIOCloseIn (void *instream)
{
    fclose (instream);
}

Value_t M_TextIOInputLine (void *instream)
{
    VProc_t *vp         = VProcSelf ();
    int bufsz           = 1024;
    char buf[bufsz];
    char *ret;

    ret = fgets (buf, bufsz+1, instream);
    if (ret == 0) {
	return M_NONE;
    }
    else  {
	return Some (vp, AllocString (vp, buf));
    }
}

void *M_TextIOOpenOut (Value_t filename)
{
    SequenceHdr_t	*filenameS = (SequenceHdr_t *)ValueToPtr(filename);

    return fopen ((char*)(filenameS->data), "w");
}

void M_TextIOCloseOut (void *outstream)
{
    fclose (outstream);
}

void M_TextIOOutput (void *outstream, void *ws)
{
    SequenceHdr_t	*str = (SequenceHdr_t *)ValueToPtr(ws);
    fprintf(outstream, "%s", (char*)(str->data));
}

void M_TextIOOutputLine (void *ws, void *outstream)
{
    SequenceHdr_t	*str = (SequenceHdr_t *)ValueToPtr(ws);
    fputs((char*)(str->data), outstream);
}

Value_t M_StringTokenize (Value_t str, Value_t sep)
{
    VProc_t             *vp = VProcSelf ();
    SequenceHdr_t	*strS = (SequenceHdr_t *)ValueToPtr(str);
    SequenceHdr_t	*sepS = (SequenceHdr_t *)ValueToPtr(sep);
    char                *strData = (char*)strS->data;
    char                *sepData = (char*)sepS->data;
    Value_t             l = M_NIL;
    char                buf[strS->len+1];

    memcpy (buf, strData, strS->len+1);
    char *token = strtok(buf, sepData);
    while(token != NULL) {
	l = Cons (vp, AllocString (vp, token), l);
	token = strtok(NULL, sepData);
    }
    return l;
}

void DebugThrow (VProc_t *vp, char *loc)
{
#ifndef NDEBUG
    SayDebug("[%2d] %s\n", vp->id, loc);
#endif
}
