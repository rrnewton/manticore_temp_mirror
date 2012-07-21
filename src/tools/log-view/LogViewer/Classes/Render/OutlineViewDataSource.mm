
/** \file OutlineViewDataSource.mm
  * \author Korei Klein
  * \date 7/27/09
  *
  */

#import "OutlineViewDataSource.h"
#import "log-desc.hxx"
#import "Exceptions.h"
#import "Box.h"
#import "LogDoc.h"
#import "Utils.h"

/// The state a checkbox should be in before a user has clicked on it
#define DEFAULT_ENABLED_STATE ( [NSNumber numberWithInt:1] )


@implementation OutlineViewDataSource



- (OutlineViewDataSource *)initWithLogDesc:(struct LogFileDesc *)descVal
				    logDoc:logDocVal
{
    if (![super init]) return nil;
    desc = descVal;
    root = desc->Root();
    logDoc = logDocVal;
    map = [[NSMutableDictionary alloc] init];
    boxes = [[NSMutableArray alloc] init];
    return self;
}


- (id)outlineView:(NSOutlineView *)outlineView
	    child:(NSInteger)index
	   ofItem:(id)item
{
    // NSLog(@"OutlineViewDataSource: returning child of item");
    if (item == nil)
    {
	if (index != 0)
	{
	    [Exceptions
	       raise:@"OutlineViewDataSource: nil has one child, asked for a child of index != 0"];
	}
	else // index == 0
	{
	   // NSLog(@"returning root");
	    EventGroupBox *b = [EventGroupBox box:(void *)root withType:GROUP];
	    [boxes addObject:b];
	    return b;
	}
    }
    if ([((EventGroupBox *) item) type] == STATE)
	[Exceptions raise:@"OutlineViewDataSource: asked for the child of a leaf node"];

    Group *g = (Group *)[((EventGroupBox *) item) unbox];
    EventGroupBox *b;
    switch (g->Kind())
    {
	case EVENT_GROUP:
	    b = [EventGroupBox box:(void *)((EventGroup *)g)->Kid(index) withType:GROUP];
	    break;
	case STATE_GROUP:
	    b = [EventGroupBox box:(void *)([NSNumber numberWithInt:index]) withType:STATE];
	    break;
	default:
	    [Exceptions raise:@"OutlineViewDataSource: asked for the child of a leaf node"];

    }
    [boxes addObject:b];
    return b;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView
   isItemExpandable:(id)item
{
    if (item == nil)
    {
	[Exceptions raise:@"OutlineViewDataSource: asked if nil was expandable"];
    }
    
    if ([((EventGroupBox *) item) type] == STATE)
	return NO;
    Group *g = (Group *)[((EventGroupBox *) item) unbox];

    switch (g->Kind()) {
	case EVENT_GROUP:
	case STATE_GROUP:
	    return YES;
	default:
	    return NO;
    }
}

- (NSInteger)outlineView:(NSOutlineView *)outlineView
  numberOfChildrenOfItem:(id)item
{
    if (item == nil) return 1;
    
    if ([((EventGroupBox *) item) type] == STATE)
    {
	[Exceptions raise:@"OutlineViewDataSource was asked for the number of children of a leaf node"];
	return -1;
    }

    Group *g = (Group *)[((EventGroupBox *) item) unbox];
    switch (g->Kind())
    {
	case EVENT_GROUP:
	    return ((EventGroup *)g)->NumKids();
	case STATE_GROUP:
	    return ((StateGroup *)g)->NumStates();
	default:
	    [Exceptions raise:@"OutlineViewDataSource was asked for the number of children of a leaf node"];
	    return -1;
    }
}

	    -(id)outlineView:(NSOutlineView *)outlineView
   objectValueForTableColumn:(NSTableColumn *)tableColumn
		      byItem:(id)item
{
    if (item == nil)
	[Exceptions raise:@"nil has no valueForTableColumn"];
    NSNumber *ident = tableColumn.identifier;
    EventGroupBox *b = (EventGroupBox *)item;
    
    if ([b type] == STATE)
    {
	/* Item represents the state of a StateGroup. */
	NSNumber *n = (NSNumber *)([b unbox]);
	StateGroup *parent = (StateGroup *)([(EventGroupBox *)[outlineView parentForItem:item] unbox]);
	return [NSString stringWithCString:parent->StateName([n intValue])
				  encoding:NSASCIIStringEncoding];
    }
    
    Group *g = (Group *)[b unbox];
    if (ident)
    {
	if (ident.intValue == 0)
	{
	    // The first column should contain the name of the group
	    NSString *s = [NSString stringWithCString:g->Desc()
					     encoding:NSASCIIStringEncoding];
	    // NSLog(@"OutlineViewDataSource: returning the description of an item: %@", s);
	    return s;
	}
	else if (ident.intValue == 1)
	{
	   // The second column should contain a checkbox indicating how enabled
	   // The given group is
	   // NSLog(@"outlineviewdatasource, returning enabled state of g");
	    return [self enabled:g];
	}
	else
	{
	    [Exceptions raise:@"OutlineViewDataSource: Table Column lacks a suitable identifier"];
	}
    }
    [Exceptions raise:@"OutlineViewDataSource: Table Column's identifier was nil"];
    return [NSNumber numberWithInt:-1];
}


/* Delegate method - called when the outlineView is about to display the given
   cell. Our job is to color the background of the given cell to match the color
   that we will draw the cell's event type as.
   
   This makes the filtering OutlineView into a color legend as well.
 */
- (void)outlineView:(NSOutlineView *)outlineView
    willDisplayCell:(id)cell
     forTableColumn:(NSTableColumn *)tableColumn
	       item:(id)item
{

    
    NSNumber *ident = tableColumn.identifier;
    if (item == nil || !ident)
	return;
    
    /* by default, don't draw the background - this allows us to short-circuit
     * return any time without worrying about setting the cell's state correctly.
     */
    [cell setDrawsBackground:NO];
    
    EventGroupBox *b = (EventGroupBox *)item;
    if (ident.intValue == 0)
    {
	/* Get the proper color for the group, and change the given cell's
	   background color to match it. */
	const char *colorName;

	NSNumber *n;
	StateGroup *parent;
	
	switch ([b type]) {
	    case STATE:
		n = (NSNumber *)([((Box *) item) unbox]);
		parent = (StateGroup *)([(EventGroupBox *)[outlineView parentForItem:item] unbox]);
		colorName = parent->StateColor([n intValue]);
		break;
	    case GROUP:
		Group *g = (Group *)[b unbox];
		switch (g->Kind())
		{
		    case INTERVAL_GROUP:
			colorName = ((IntervalGroup *) g)->Color();
			break;
		    case DEPENDENT_GROUP:
			colorName = ((DependentGroup *) g)->Color();
			break;
		    case STATE_GROUP: 
		    case EVENT_GROUP:
		    default:
			return;
		}
		break;

	}
	NSColor *bkgndColor = [Utils colorFromFormatString:colorName];
	[cell setBackgroundColor:bkgndColor];
	[cell setDrawsBackground:YES];
    }
    else if (ident.intValue == 1)
    {
	if ([b type] == STATE)
	{
	    /* Don't display the checkbox. */
	    [cell setTransparent:YES];
	    [cell setEnabled:NO];
	}
	else {
	    [cell setTransparent:NO];
	    [cell setEnabled:YES];
	}

    }

}



#pragma mark Heirarchical Enabled State Management
/*

When the user clicks on a checkbox, there is a complicated set of rules determining
what happens to the other checkboxes.

The state of a node n is either
    0. 0/unchecked/disabled
    1. 1/checked/enabled
    2. -1/semi-checked/partially-enabled

In this comment is a description of the intended behavior, and below is an implementation of how to achieve it.

The tree of groups along with their enabled states must satisfy the following properties:
    0. if a parent node n is in state s then
	a. if s == 1 then all children of n must be in state 1
	b. if s == 0 then all children of n must be in state 0
	c. if s == -1 then n must have one descendant in state 1 and one descendant in state 0

When a user clicks on a checkbox, the following tabled determines the state the checkbox must move
into based on the state it is already in
    state_when_clicked		next_state
    0				1
    1				0
    -1				1

The states of the rest of the checkboxes will then change to have the following 3 properties
    0. The clicked group remains in the state it transitioned into (according to the above table)
    1. The tree of groups satisfies the properties it must satisfy
    2. There are as few differences as possible between the old tree and the new tree such that
	    the above two properties are satisfied

These 3 properties uniquely determine the behavior of the tree when clicking on boxes


*/



/// Modify the mapping, do not follow any logic for propogating the effect of a change
- (void)mapState:(NSNumber *)n forGroup:(Group *)g
{
    const char *s = g->Desc();
    NSString *S = [NSString stringWithCString:s encoding:NSASCIIStringEncoding];
    S = [[NSString alloc] initWithString:S];
    //NSLog(@"setting object %@, for key %@ in map", n, S);
    [map setObject:n forKey:S];
}

/// Change the state of the parent (g) and all its ancestors to reflect
/// the states of their descendents
- (void)setParentByKids:(Group *)g
{
    if (g == NULL) return;
    if (g->Kind() != EVENT_GROUP)
    {
	[Exceptions raise:@"OutlineViewDataSource: Found a parent which has no children.  Impossible!"];
    }
    EventGroup *parent = (EventGroup *)g;
    if (parent->NumKids() == 0)
    {
	[Exceptions raise:@"OutlineViewDataSource: setParentByKids was called with a childless group"];
    }

    // The following 2 BOOL will have the indicated properties at the conclusion
    // of the next for loop
    BOOL found_0 = 0; // 1 iff any descendents are 0
    BOOL found_1 = 0; // 1 iff any descendents are 1
    for (int i = 0; i < parent->NumKids(); ++i)
    {
	int cur_case = [self enabled:parent->Kid(i)].intValue;
	switch (cur_case)
	{
	    case 0:
		found_0 = 1;
		break;
	    case 1:
		found_1 = 1;
		break;
	    case -1:
		found_0 = found_1 = 1;
		break;
	    default:
		NSLog(@"wierd case %d", cur_case);
		[Exceptions raise:@"failure impossible case"];
	}
    }

    // Will hold the state g should be in at the conclusion of the next cascading if statement
    NSNumber *stateVal;
    if (found_0 && !found_1)
    {
	stateVal = [NSNumber numberWithInt:0];
    }
    else if (!found_0 && found_1)
    {
	stateVal = [NSNumber numberWithInt:1];
    }
    else if (found_0 && found_1)
    {
	stateVal = [NSNumber numberWithInt:-1];
    }
    else
    {
	[Exceptions raise:@"Failure, impossible case"];
    }

    [self mapState:stateVal forGroup:g];

    [self setParentByKids:parent->Parent()]; //< the grandparent
}


/// Modify the mapping, follow the logic for propogating the effect of the change
/// Assume: all the parents of group g are in the propert state
- (void)propogateButtonStateDownward:(NSNumber *)n forGroup:(Group *)g
{
    [self mapState:n forGroup:g];
    if (n.intValue != -1 && (g->Kind() == EVENT_GROUP))
    {
	EventGroup *G = (EventGroup *)g;
	for (int i = 0; i < G->NumKids(); ++i)
	{
	    [self propogateButtonStateDownward:n forGroup:G->Kid(i)];
	}
    }
}


/// Modify the mapping, follow the logic for propogating the effect of the change
- (void)setButtonState:(NSNumber *)n forGroup:(Group *)g
{
    [self propogateButtonStateDownward:n forGroup:g];
    [self setParentByKids:g->Parent()];
}

- (void)outlineView:(NSOutlineView *)outlineView
     setObjectValue:(id)object
     forTableColumn:(NSTableColumn *)tableColumn
	     byItem:(id)item
{
    if (item == nil)
	[Exceptions raise:@"OutlineView: passed a nil item to set"];
    NSNumber *ident = tableColumn.identifier;
    if (ident == nil)
	[Exceptions raise:@"Table column lacks an identifier"];
    if (ident.intValue != 1)
	[Exceptions raise:@"Can't edit a table column whose identifier is not 1"];
    EventGroupBox *b = (EventGroupBox *)item;
    if ([b type] == STATE)
	return;
    Group *g = (Group *)([item unbox]);
    NSNumber *n = (NSNumber *)object;

    // Can't allow users to set the button to mixed
    // The button can only be set to mixed internally
    if (n.intValue == -1)
    {
	[self setButtonState:[NSNumber numberWithInt:1] forGroup:g];
    }
    else
    {
	[self setButtonState:n forGroup:g];
    }

    outlineView.needsDisplay = true;
    [logDoc flush];
}


/// Returns the state of the checkbox corresponding to a group g
- (NSNumber *)enabled:(struct Group *)g
{
    NSString *S = [NSString stringWithCString:g->Desc() encoding:NSASCIIStringEncoding];
    NSNumber *ret = [map objectForKey:S];

    if (ret == nil)
    {
	return DEFAULT_ENABLED_STATE;
    }
    else
    {
	return ret;
    }
}


@end



