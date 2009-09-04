/** \file  SummaryView.mm
 * \author Korei Klein
 * \date 8/17/09
 *
 */

#import "SummaryView.h"
#import "Pie.h"
#import "PieSlice.h"
#import "Summary.h"
#import "Exceptions.h"
#import "log-desc.hxx"
#import "Utils.h"


@implementation SummaryView

- (id)initWithFrame:(NSRect)frame
{
    [Exceptions raise:@"SummaryView: bad initializer"];
    return self;
}


- (SummaryView *)initWithFrame:(NSRect)frame
		    andSummary:(Summary *)summaryVal
		   columnWidth:(CGFloat)widthVal
{
    if (![super initWithFrame:frame]) return nil;


    summary = summaryVal;
    width = widthVal;


    assert ( self.bounds.size.width >= summary.pies.count * width);


    return self;
}


/// Configuration algorithm for determining the color to use to represent a given consumer.
/// Currently uses color information loaded into the group hierarchy from the log-view.json file.
- (NSColor *)colorForConsumer:(NSObject *)consumer
{
    NSNumber *n = (NSNumber *)consumer;
    int i = n.intValue;
    StateGroup *g = summary.resource;
    const char *s = g->StateColor(i);
    NSColor *c = [Utils colorFromFormatString:s];
    return c;
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


    assert ( bounds.size.width >= summary.pies.count * width );

    NSArray *pies = summary.pies;
 //   NSLog(@"pies is %@: \n and summary is %@", pies, summary);
   // NSLog(@"drawing %d pies each of width %f", pies.count, width);
    for (int i = 0; i < pies.count; ++i)
    {
	CGFloat cur_x = bounds.origin.x + i * width;
	Pie *pie = [pies objectAtIndex:i];
	NSArray *consumers = pie.consumers;

	CGFloat cur_y = bounds.origin.y;
	for (int j = 0; j < consumers.count; ++j)
	{
	    // The below is commented out because it is to stringent a requirement,
	    // cur_y might be a tiny bit to big,
	    //	    We can leave it commented out because cur_y will not often
	    //	    be much larger than bounds.origin.y + bounds.size.height
	    // assert (cur_y < bounds.origin.y + bounds.size.height);

	    PieSlice *pieSlice = [consumers objectAtIndex:j];
	    CGFloat cur_height = bounds.size.height * pieSlice.fraction;

	    NSRect r = NSMakeRect(cur_x, cur_y, width, cur_height);
	    NSColor *c = [self colorForConsumer:pieSlice.consumer];
	    [self fillRect:r withColor:c];

	    cur_y += cur_height;

	}
    }
}

@end




