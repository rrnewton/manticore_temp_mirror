/*! \file State.m
 \author Korei Klein
 \date 7/7/09
 */

#import "State.h"

#pragma mark Defaults
/// Color of states
#define DEFAULT_STATE_COLOR ([NSColor blueColor])



@implementation State

@synthesize rect;
@synthesize start;
@synthesize end;

#pragma mark Initializations

- (State *)initWithRect:(NSRect)r
		  color:(NSColor *)c
		  start:(event *)startVal
		    end:(event *)endVal;
{
	if (![super init])
		return nil;
	rect = r;
	color = c;
	start = startVal;
	end = endVal;

	return self;
}

#pragma mark EventShape Methods

- (void)drawShape
{
	[color set];
	[NSBezierPath fillRect:rect];
}


- (BOOL)containsPoint:(NSPoint)p
{
	return
		(
		p.x >= rect.origin.x &&
		p.x <= rect.origin.x + rect.size.width &&
		p.y >= rect.origin.y &&
		p.y <= rect.origin.y + rect.size.height
		);
		
}

@end
