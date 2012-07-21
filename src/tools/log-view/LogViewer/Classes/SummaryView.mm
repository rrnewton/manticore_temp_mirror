/** \file  SummaryView.mm
 * \author Korei Klein
 * \date 8/17/09
 *
 */

#import "SummaryView.h"
#import "Pie.h"
#import "Summary.h"
#import "Exceptions.h"
#import "log-desc.hxx"
#import "Utils.h"


@implementation SummaryView

@synthesize logDoc;
@synthesize summary;
@synthesize width;
@synthesize hilightInterval;

- (id)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {

	trackingArea = [[NSTrackingArea alloc] initWithRect:frameRect
						    options:NSTrackingMouseMoved | NSTrackingActiveInActiveApp
						      owner:self
						   userInfo:nil];
	[self addTrackingArea:trackingArea];
    }
    
    return self;
}

- (void)setHilightInterval:(struct LogInterval *)newHilightInterval
{
    
    hilightInterval = newHilightInterval;
    [self removeTrackingArea:trackingArea];
    trackingArea = [[NSTrackingArea alloc] initWithRect:[self hilightRect]
						options:NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited | NSTrackingActiveInActiveApp
						  owner:self
					       userInfo:nil];
    [self addTrackingArea:trackingArea];
}


/// Configuration algorithm for determining the color to use to represent a given consumer.
/// Currently uses color information loaded into the group hierarchy from the log-view.json file.
- (NSColor *)colorForConsumer:(int)consumer;
{
    StateGroup *g = summary.resource;
    const char *s = g->StateColor(consumer);
    NSColor *c = [Utils colorFromFormatString:s];
    return c;
}

- (NSRect)hilightRect
{
    NSRect hilightRect = [self bounds];
    hilightRect.origin.x = round((self.bounds.size.width / [summary logInterval].width) * hilightInterval->x);
    hilightRect.size.width = round((self.bounds.size.width / [summary logInterval].width) * hilightInterval->width);
    return hilightRect;
}

/// Draw a single horizontal slice of the summary view
/**
    The drawing of the summary view is divided up into thin rectangles.
    Each rectangle's height is the height of the summary view, and its width is small.
    Each rectangle represents a single pie.
    Within each rectangle there are smaller rectangles.
	Each of these smaller rectangles represents a consumer of that pie.
	This method fills in one of those smaller rectangles with a color.
*/
- (void)fillRect:(NSRect)r withColor:(NSColor *)c
{
    // Ugly?!
    // Yet Simple!

    // To prettify this drawing, try filling the rectangle with small squares
    // which have space in between them

    [c set];
    [NSBezierPath fillRect:r];
}

- (void)drawRect:(NSRect)rect
{
   // NSLog(@"summary view is drawing itself");
    NSRect bounds = self.bounds;
    [[NSColor blackColor] set];
    [NSBezierPath fillRect:bounds];


    //assert ( bounds.size.width >= summary.pies.count * width );

    NSArray *pies = summary.pies;
 //   NSLog(@"pies is %@: \n and summary is %@", pies, summary);
   // NSLog(@"drawing %d pies each of width %f", pies.count, width);
    for (unsigned int i = 0; i < pies.count; ++i)
    {
	CGFloat cur_x = bounds.origin.x + i * width;
	Pie *pie = [pies objectAtIndex:i];
	PieSlice_t *consumers = pie.consumers;

	CGFloat cur_y = bounds.origin.y;
	for (unsigned int j = 0; j < pie.nConsumers; ++j)
	{
	    // The below is commented out because it is to stringent a requirement,
	    // cur_y might be a tiny bit to big,
	    //	    We can leave it commented out because cur_y will not often
	    //	    be much larger than bounds.origin.y + bounds.size.height
	    // assert (cur_y < bounds.origin.y + bounds.size.height);

	    PieSlice_t *slice = consumers + j;
	    
	    CGFloat cur_height = bounds.size.height * slice->fraction;

	    NSRect r = NSMakeRect(cur_x, cur_y, width, cur_height);
	    NSColor *c = [self colorForConsumer:slice->consumer];
	    [self fillRect:r withColor:c];

	    cur_y += cur_height;

	}
    }
    if (hilightInterval && hilightInterval->width != summary.logInterval.width)
    {
	[[[NSColor blueColor] colorWithAlphaComponent:0.6] set];
	[NSBezierPath fillRect:[self hilightRect]];
    }
}

- (void)mouseMoved:(NSEvent *)e
{
    [super mouseMoved:e];
    NSPoint p = [self convertPoint:e.locationInWindow fromView:nil];
    NSRect hilightRect = [self hilightRect];

    if (NSPointInRect(p, hilightRect))
    {
	if (p.x == hilightRect.origin.x ||
	    p.x == hilightRect.origin.x + self.hilightRect.size.width)
	{
	    [[NSCursor resizeLeftRightCursor] set];
	}
	else
	{
	    [[NSCursor openHandCursor] set];
	}
    }
    else
    {
	[[NSCursor arrowCursor] set];
    }
}

- (void)mouseExited:(NSEvent *)e
{
    [super mouseExited:e];
    [[NSCursor arrowCursor] set];
}

- (void)mouseEntered:(NSEvent *)e
{
    [super mouseEntered:e];
    [[NSCursor resizeLeftRightCursor] set];
}

- (void)mouseDown:(NSEvent *)e
{
    [super mouseDown:e];
    NSPoint p = [self convertPoint:e.locationInWindow fromView:nil];
    
    if (NSPointInRect(p, [self hilightRect]))
    {
	dragging = YES;
	dragStarted = dragContinued = p;
	[[NSCursor closedHandCursor] set];
    }
    else {
	dragging = NO;
    }
}

- (void)mouseDragged:(NSEvent *)e
{    
    [super mouseDragged:e];
    NSPoint p = [self convertPoint:e.locationInWindow fromView:nil];
    
    if (dragging)
    {
	[[NSCursor closedHandCursor] set];

	CGFloat diff = p.x - dragContinued.x;
	dragContinued = p;
	struct LogInterval *logInterval = [[self logDoc] logInterval];
	struct LogInterval *maxLogInterval = [[self logDoc] maxLogInterval];
	
	int moveBy = ([summary logInterval].width / self.bounds.size.width) * diff;
	
	/* Don't allow the user to drag past either end of the screen. */
	if (moveBy < 0 && abs(moveBy) > logInterval->x)
	    logInterval->x = 0;
	else if (moveBy > 0 && moveBy + logInterval->x + logInterval->width > maxLogInterval->width)
	    logInterval->x = maxLogInterval->width - logInterval->width;
	else
	    logInterval->x += moveBy;

		
	[[self logDoc] flush];
	
    }
    

}

- (void)mouseUp:(NSEvent *)e
{
    [super mouseUp:e];
    return;
    
    /*
    NSPoint p = [self convertPoint:e.locationInWindow fromView:nil];
    
    if (dragging && p.x != dragStarted.x)
    {
	CGFloat diff = p.x - dragStarted.x;
	struct LogInterval *logInterval = [[self logDoc] logInterval];
	struct LogInterval *maxLogInterval = [[self logDoc] maxLogInterval];

	logInterval->x += ([summary logInterval].width / self.bounds.size.width) * diff;
	if (logInterval->x <= 0)
	    logInterval->x = 1;
	if (logInterval->x + logInterval->width > maxLogInterval->x + maxLogInterval->width)
	    logInterval->x = maxLogInterval->x + maxLogInterval->width - logInterval->width;
	[[self logDoc] flush];
    }
     */
}

@end




