/*! \file LogDoc.mm
 *
 * \author Korei Klein
 */

/*
 * COPYRIGHT (c) 2009 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 */

#import "LogDoc.h"
#import "LogData.h"
#import "ViewController.h"
#import "default-log-paths.h"
#import "Exceptions.h"
#import "LogView.h"
#import "OutlineViewDataSource.h"
#import "log-desc.hxx"
#import "DetailAccess.h"
#import "DetailInfoController.h"
#import "DetailInfoView.h"
#import "ShapeRep.h"
#import "GroupFilter.h"
#import "Summary.h"
#import "SummaryView.h"
#import "Box.h"
#import "Pie.h"

/* keep a cache of the log-file description structure.  Note that this
 * code will have to be changed if we ever want to support multiple
 * descriptions.
 */
static LogFileDesc *LFDCache = 0;

/// Name of the nib file which contains the detail info view
#define DETAIL_INFO_NIB_NAME ( @"DetailInfo" )

/// Name of the nib whose views this controller will manage
#define WINDOW_NIB_NAME ( @"LogDoc" )

/// Determines how much bigger/smaller the view get when zooming in/out
/// sqrt(10) is a fun ZOOM_FACTOR
#define DEFAULT_ZOOM_FACTOR ( 3.16227 )

/// Do not display events whose timespan (in floats) would be less than MIN_LOGINTERVAL_WIDTH
#define MIN_LOGINTERVAL_WIDTH ( 20 )


@implementation LogDoc


#pragma mark Synthesis
@synthesize zoomFactor;
@synthesize logView;
@synthesize logData;
@synthesize outlineView;
@synthesize outlineViewDataSource;
@synthesize logInterval;
@synthesize maxLogInterval;
@synthesize enabled;
@synthesize viewController;



- (GroupFilter *)filter
{
    return outlineViewDataSource;
}

- (LogFileDesc *)logDesc
{
    return LFDCache;
}

- (IBAction)drewTicks:(LogView *)sender
{
    //[timeDisplay drewTicks:sender];
}

/// Cause logView to display logData according to currently set parameters
- (void)flush
{
    [logView displayInterval:logInterval
		 atZoomLevel:[self zoomLevelForInterval:logInterval]
		 fromLogData:self.logData
		  filteredBy:self.filter];
    
    [summaryView setHilightInterval:logInterval];
    if (summaryView.summary)
    {
	[summaryView setNeedsDisplay:YES];
	return;
    }

    StateGroup *resourceState;
    {
	if (logData.allStates == NULL)
    	{
    	    [Exceptions raise:@"LogDoc: can't flush when logData has no allStates property"];
    	}
    	if (logData.allStates.count <= 0)
    	{
    	    [Exceptions raise:@"LogDoc: can't flush when logData's allStates has no first element"];
    	}
    	Box *b = [logData.allStates objectAtIndex:0];
	resourceState = (StateGroup *) [b unbox];
    }

   // NSLog(@"RESOURCE state is %s", resourceState->Desc());

#pragma mark Display Summary View

    CGFloat summary_view_column_width = DEFAULT_SUMMARY_VIEW_COLUMN_WIDTH;
    double viewWidth = scrollView.bounds.size.width;
    double scale = logInterval->width / viewWidth;
    
    /* Construct a summary by averaging the summaries for all VProcs. */
    Summary *tmpSummary;
    for (unsigned int i = 0; i < [logData nVProcs]; i++)
    {
	tmpSummary = [Summary coarseSummaryFromLogData:logData
					      forState:resourceState
					      forVProc:i
					      withSize:scale *     summary_view_column_width
					   andInterval:*logInterval
					     andNumber:viewWidth / summary_view_column_width];
	if (i == 0)
	{
	    summary = tmpSummary;
	}
	else
	{
	    unsigned int nPies = [[tmpSummary pies] count];
	    assert(nPies == [[summary pies] count]);
	    Pie *curPie;
	    for (unsigned int j = 0; j < nPies; j++)
	    {
		curPie = [[summary pies] objectAtIndex:j];
		// it's OK to just add these pies together, since they're all
		// already guaranteed to be stochastic.
		[curPie increaseBy:[[tmpSummary pies] objectAtIndex:j]];
	    }
	}
    }
    for (unsigned int i = 0; i < [[summary pies] count]; i++)
    {
	[[[summary pies] objectAtIndex:i] divideBy:[logData nVProcs]];
	[[[summary pies] objectAtIndex:i] assertStochastic];
    }
    [summaryView setSummary:summary];
    [summaryView setWidth:summary_view_column_width];
    [summaryView setLogDoc:self];
    
    NSRect frame = summaryView.bounds;
    frame.size.width = viewWidth;

   // [summaryView setFrame:frame];



    summaryView.needsDisplay = true;

    logView.needsDisplay = true;
}
- (NSString *)filename
{
    return logData.filename;
}

- (void)setNilValueForKey:(NSString *)key
{
    if ([key isEqualToString:@"horizontalPosition"])
	self.horizontalPosition = 0;
    else
	[super setNilValueForKey:key];
}

- (void)setHorizontalPosition:(float)n
{
  //  NSLog(@"LogDoc is setting the horizontal position to %f", n);
    horizontalPosition = n;
}
- (float)horizontalPosition
{
 //   NSLog(@"LogDoc is returning the horizontal position");
    return horizontalPosition;
}

#pragma mark Initializations
+ (void)initialize
{
    LFDCache = LoadLogDesc(DEFAULT_LOG_EVENTS_PATH, DEFAULT_LOG_VIEW_PATH);
    if (LFDCache == 0)
    {
	[Exceptions raise:@"Could not load the two log description files"];
    }

}

- (LogDoc *)init
{
    if (![super init]) return nil;

    logData = nil;
   // NSLog(@"LogDoc: setting enabled to false");
    logInterval = nil;
    zoomFactor = DEFAULT_ZOOM_FACTOR;
    enabled = false;

    detailInfoController = nil;


    return self;
}

/** When logView is to display some portion of LogData for the first time
  * it needs to know what portion of the data to display.
  * Configure how that portion is to be computed by implementing initialLogInterval
  */
- (struct LogInterval *)initialLogInterval:(LogData *)logDataVal
{
    struct LogInterval *i = (LogInterval *) malloc(sizeof(struct LogInterval));
    i->x = 0;
    i->width = logDataVal.lastTime - logDataVal.firstTime;
    return i;
}

#pragma mark logData Initialization


- (BOOL)readFromURL:(NSURL *)absoluteURL ofType:(NSString *)typeName error:(NSError **)outError
{

    // Get the filename
    if (!absoluteURL.isFileURL)
    {
	[Exceptions raise:@"LogFile was asked to read data that was not from a file"];
    }
    NSString *filename = absoluteURL.absoluteString;
   // NSLog(@" URL filename %@", filename);
    filename = [filename substringFromIndex:16];
   // NSLog(@" actual filename is %@", filename);
    if (!filename)
    {
	[Exceptions raise:@"LogFile could not get a name for given fileWrapper"];
    }

    logData = [[LogData alloc] initWithFilename:filename
				 andLogFileDesc:self.logDesc];
    // Initialize logInterval according to the initialLogInterval configuration function
    self.logInterval = [self initialLogInterval:logData];
    maxLogInterval = (LogInterval *) malloc(sizeof(struct LogInterval));
    *maxLogInterval = *self.logInterval;


    outlineViewDataSource = [[OutlineViewDataSource alloc]
			     initWithLogDesc:self.logDesc
			     logDoc:self];
    
   // NSLog(@"LogDoc: setting enabled = true");
    enabled = true;

    return YES;
}


- (void)windowControllerDidLoadNib:(NSWindowController *)windowController
{
    [super windowControllerDidLoadNib:windowController];

    if (!logView) [Exceptions raise:@"LogDoc was not properly initialized with a logView"];
    if (!outlineView) [Exceptions raise:@"LogDoc was not properly initialized with a outlineView"];
    

#pragma mark tableColumns Initialization
    NSArray *columns = outlineView.tableColumns;
    int i = 0;
    for (NSTableColumn *column in columns)
    {
	if (i >= 2) [Exceptions raise:@"Too many columns in NSOutlineView"];
	
	column.identifier = [NSNumber numberWithInt:i];
	
	++i;
    }

    if (self.enabled)
    {

	// Because some of the UI is created programmatically and some of the UI is created
	// in interface builder, it is necessary to do a small dance here to get things into the right places
	
	detailInfoController = [[DetailInfoController alloc] initWithLogDesc:[self logDesc]];
	//[detailInfoController showWindow:self];

	
	if (!outlineViewDataSource)
	{
	    NSLog(@"enabled state = %d", self.enabled);

	    [Exceptions raise:@"Did not have an initialized outlineViewDataSource while enabled"];
	}
	outlineView.dataSource = outlineViewDataSource;
	outlineView.delegate = outlineViewDataSource;
	[outlineView expandItem:nil expandChildren:YES];
		
	[self flush];
	
	//NSLog(@"Log Doc has logInterval %qu, %qu, for bounds from %f to %f",
	//    logInterval->x, logInterval->width, logView.splitView.shapeBounds.origin.x,
	//      logView.splitView.shapeBounds.size.width);
	
	//NSLog(@"LogDoc is opening a drawer %@", drawer);
	[drawer open];

    }
}


#pragma mark NSDocument Settings

/// It is not possible to edit log files
- (BOOL)isDocumentEdited
{
    return NO;
}


- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError
{
    [Exceptions raise:@"LogDoc can't write data"];
    return nil;
}

- (NSString *)windowNibName
{
    return WINDOW_NIB_NAME;
}

#pragma mark Zooming

/// The largest number of nanoseconds that can be displayed at deep zoom, given in uint64_t
#define MAX_DEEP_ZOOM_WIDTH ( ULLONG_MAX )
/// The largest number of nanoseconds that can be displayed at medium zoom
#define MAX_MEDIUM_ZOOM_WIDTH ( 10000000 )
- (enum ZoomLevel)zoomLevelForInterval:(struct LogInterval *)logIntervalVal
{
    uint64_t width = logIntervalVal->width;
    if (width < MAX_DEEP_ZOOM_WIDTH)
    {
	return zoomLevelDeep;
    }
    else if (width < MAX_MEDIUM_ZOOM_WIDTH)
    {
	return zoomLevelMedium;
    }
    else
    {
	return zoomLevelShallow;
    }
}

- (void)printLogInterval
{
   // NSLog(@"LogDoc->LogInterval = { %qu, %qu }", logInterval->x, logInterval->width);
}

/// Take a point in the logData to the corresponding point in the logView
- (CGFloat)image:(uint64_t)p
{
    NSRect shapeBounds = self.logView.splitView.bounds;
    double scale = shapeBounds.size.width / (logInterval->width);
    return shapeBounds.origin.x + scale * (p - logInterval->x);
}

/// Take a point in the logView to the corresponding point in the logData
- (uint64_t)preImage:(CGFloat)p
{
    NSRect shapeBounds = logView.splitView.bounds;
    double scale = logInterval->width / shapeBounds.size.width;
    return logInterval->x + scale * (p - shapeBounds.origin.x);
}

/// Horizontal midpoint of an NSRect
- (CGFloat)xMidPoint:(NSRect)r
{
    return r.origin.x + r.size.width / 2;
}


- (void)zoomBy:(double)scale aboutPivot:(uint64_t)pivot
{
    /* Change the logInterval to reflect the zoom. Make sure we don't go past
     * the left or right edge of the data. */
    
    if (pivot < scale * (pivot - logInterval->x))
	logInterval->x = 0;
    else
	logInterval->x = pivot - scale * (pivot - logInterval->x);
    
    logInterval->width = logInterval->width * scale;

    if (logInterval->x + logInterval->width > maxLogInterval->x + maxLogInterval->width)
    {
	logInterval->width = maxLogInterval->x + maxLogInterval->width - logInterval->x;
    }
    [self flush];
}
- (void)zoomBy:(double)scale
{
    uint64_t pivot = [self preImage:[self xMidPoint:logView.splitView.visibleRect]];
    [self zoomBy:scale aboutPivot:pivot];
}

- (void)zoomInAboutPivot:(uint64_t)pivot
{
    [self zoomBy:1 / zoomFactor aboutPivot:pivot];
}
- (void)zoomOutAboutPivot:(uint64_t)pivot
{
    [self zoomBy:1 * zoomFactor aboutPivot:pivot];
}



- (IBAction)zoomIn:(id)sender
{
    self.printLogInterval;
    double scale = 1 / zoomFactor;
    if (scale * logInterval->width < MIN_LOGINTERVAL_WIDTH)
    {
	NSLog(@"Not continuing to zoom.  Reached minimum width");
	return;
    }
    [self zoomBy:scale];
    self.printLogInterval;
}

- (IBAction)zoomOut:(id)sender
{
    self.printLogInterval;
    double scale = 1 * zoomFactor;
    [self zoomBy:scale];
    self.printLogInterval;
}



- (IBAction)zoom:(NSSegmentedControl *)sender
{
    NSInteger n = sender.selectedSegment;
    if (n == 0)
    {
	[self zoomOut:sender];
    }
    else if (n == 1)
    {
	[self zoomIn:sender];
    }
    else
    {
	[Exceptions raise:@"LogDoc: asked to zoom, but no segment of the sender is selected"];
    }
}

// For debugging purposes
uint64_t g_counter = 0;

- (BOOL)isInInterval:(Detail)d
{
    uint64_t fst = logInterval->x;
    uint64_t lst = logInterval->width + fst;
    Group *g = Detail_Type(d);
    event *c, *b;
    switch (g->Kind()) {
        case EVENT_GROUP: {
	    uint64_t a = Event_Time(*Detail_Simple_value(d));
	    return (fst <= a) && (a <= lst);
	  } break;
	case INTERVAL_GROUP:
	    c = Detail_Interval_start(d);
	    b = Detail_Interval_end(d);
	    assert(c != NULL);
	    if (b == NULL) return true;
	    if ((Event_Time(*c) > lst) || (Event_Time(*b) < fst))
		return false;
	    else
		return true;
	    break;
	case STATE_GROUP:
	    c = Detail_State_start(d);
	    b = Detail_State_end(d);
	    if (c == NULL && b == NULL) 
	    {
		NSLog(@"State group spans entire interval. including.");
		return true;
	    }
	    if (c == NULL) {
		//NSLog(@"State group begins before start of interval. Time %qx, first is %qx", b->timestamp, fst);
		/*FIXME: below conditional is commented out, because it seems
		  to break things. try zooming in with it commented in - you'll
		  notice that there is empty space on the left side of the main
		  display, because this conditional is returning false when it
		  shouldn't be. */
		return Event_Time(*b) >= fst;
	    }
	    if (b == NULL) {
		return Event_Time(*c) <= lst;
	    }
	    if ((Event_Time(*c) > lst) || (Event_Time(*b) < fst))
		return false;
	    else
		return true;
	    break;
	case DEPENDENT_GROUP:
	    return false; /// XXX FIXME
    }

    //NSLog(@"g = %s, g->Kind() = %d", g->Desc(), g->Kind());
    ++g_counter;
    // int n = * ((int *)0);
    //NSLog(@"%d", n);
    [Exceptions raise:@"Controll should not reach here"];
    return false;
}


#pragma mark Detail Info

- (void)displayDetail:(EventShape *)d
{
    [detailInfoController displayDetail:d];
}


#pragma mark Printing

- (void)printShowingPrintPanel:(BOOL)showPanels
{
    NSLog(@"LogDoc is being asked to print");
    NSPrintOperation *op = [NSPrintOperation
			    printOperationWithView:scrollView
			    printInfo:[self printInfo]];
    op.showsPrintPanel = showPanels;

    [self runModalPrintOperation:op
			delegate:nil
		  didRunSelector:NULL
		     contextInfo:NULL];
}


- (IBAction)showDetailWindow:(id)sender
{
    [detailInfoController showWindow:self];
}


@end





