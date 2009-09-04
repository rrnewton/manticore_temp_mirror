/** \file  Summary.mm
\author Korei Klein
\date 8/13/09

*/

#import "Summary.h"
#import "VProc.h"
#import "log-desc.hxx"
#import "Pie.h"
#import "Exceptions.h"
#import "DetailEnumerator.h"
#import "Detail.h"
#import "DetailAccess.h"



@implementation Summary

/// Size of the window used in the boxcar averaging algorithm
#define DEFAULT_BOXCAR_WINDOW ( 10 )
/// Weight placed on the preexisting average in the Exponential decay algorithm
#define DEFAULT_EXP_DECAY_WEIGHT ( 0.6 )
/// Size of a block of partition in the partitioning algorithm
#define DEFAULT_PARTITION_BLOCK ( 30 )

#pragma mark Synthesis

@synthesize pies;

@synthesize resource;
@synthesize size;
@synthesize start;

#pragma mark Initializations

- (Summary *)initWithSize:(uint64_t)s
		 andStart:(uint64_t)st
	       andResource:(StateGroup *)res
{
    if (![super init]) return nil;

    resource = res;
    size = s;
    start = st;
    pies = [[NSMutableArray alloc] init];

    return self;
}

/*
 Internal functions for converting to a coarser summary.
 Each corresponds to a different algorithm for averaging data.
 */

/// Partition into blocks of size block and average each block
/// The new summary is 1/block the size of the old summary
/// Has tolerance for weird egde cases
- (Summary *)coarsePartition:(int)block group:(StateGroup *)g
{

    Summary *ret = [[Summary alloc] initWithSize:size
					andStart:start
				     andResource:resource];
    NSMutableArray *arr = ret.pies;

    int n = pies.count;

    for (int i = 0; i + block <= n; i += block)
    {
	Pie *tot = [Pie emptyForStateGroup:g];
	for (int j = i; j < i + block; ++j)
	{
	    Pie *pie = [pies objectAtIndex:j];
	    [tot increaseBy:pie];
	}
	[tot divideBy:block];
	[tot assertStochastic];
	[arr addObject:tot];
    }
    return ret;

}


/// Boxcar average of size window
/// The new summary's size is the old summary's size - window + 1
- (Summary *)coarseBoxcar:(int)window group:(StateGroup *)g
{
    Summary *ret = [[Summary alloc] initWithSize:size
					andStart:start
				     andResource:resource];
    NSMutableArray *arr = ret.pies;

    if (pies.count < window)
    {
	[Exceptions raise:@"Summary.mm: coarseBoxcar was called on an array \
	 smaller than the boxcar width"];
    }

    // Initialize the first element of arr
    Pie *tot = [Pie emptyForStateGroup:g];
    for (int i = 0; i < window; ++i)
    {
	Pie *pie = [pies objectAtIndex:i];
	[tot increaseBy:pie];
    }
    [tot divideBy:window];
    [tot assertStochastic];
    [arr addObject:tot];

    // Initialize the rest of arr
    for (int i = 0; i < pies.count - window; ++i)
    {
	[tot multiplyBy:window];  //< Undo the division of tot from before

	// Shift the boxcar window by 1
	[tot decreaseBy:[pies objectAtIndex:i]];
	[tot increaseBy:[pies objectAtIndex:(i + window)]];

	[tot divideBy:window];
	[tot assertStochastic];
	[arr addObject:tot];
    }

    return ret;
}
/// Exponential decay where the existing average is weighted at weight
/// Returns a summary of the same size
- (Summary *)coarseExpDecay:(float)weight
{
    assert ( 0 < weight && weight < 1 );

    Summary *ret = [[Summary alloc] initWithSize:size
					andStart:start
				     andResource:resource];
    NSMutableArray *arr = ret.pies;
    assert (pies.count > 0);

    Pie *tot = [[pies objectAtIndex:0] copy];
    [arr addObject:tot];

    for (int i = 1; i < pies.count; ++i)
    {
	Pie *pie = [[pies objectAtIndex:i] copy];
	[tot multiplyBy:weight];
	[pie multiplyBy:1.0 - weight];
	[tot increaseBy:pie];
	[tot assertStochastic];
	[arr addObject:tot];
    }

    return ret;
}




/** The different options for how to implement coarseSummaryFromLogData
 */

+ (Summary *)coarseSummaryFromLogDataExpDecay:(LogData *)logData
				     forState:(StateGroup *)state
				     forVProc:(int32_t)vp
				     withSize:(uint64_t)s
				     andStart:(uint64_t)st
				    andNumber:(uint64_t)n
{
    double weight = DEFAULT_EXP_DECAY_WEIGHT;
    uint64_t size = s * (n / n);
    Summary *ret = [Summary fineSummaryFromLogData:logData
					  forState:state
					  forVProc:vp
					  withSize:size
    					  andStart:st
    					 andNumber:n];
    ret = [ret coarseExpDecay:weight];
    return ret;
}

+ (Summary *)coarseSummaryFromLogDataBoxcar:(LogData *)logData
				   forState:(StateGroup *)state
				   forVProc:(int32_t)vp
				   withSize:(uint64_t)s
				   andStart:(uint64_t)st
				  andNumber:(uint64_t)n
{
    int window = DEFAULT_BOXCAR_WINDOW;
    uint64_t fine_n = n + window - 1;
    uint64_t size = s * ( n / fine_n );
    Summary * ret = [Summary fineSummaryFromLogData:logData
					   forState:state
					   forVProc:vp
					   withSize:size
    					   andStart:st
    					  andNumber:fine_n];
    ret = [ret coarseBoxcar:window group:state];
    return ret;
}
+ (Summary *)coarseSummaryFromLogDataPartition:(LogData *)logData
				      forState:(StateGroup *)state
				      forVProc:(int32_t)vp
				      withSize:(uint64_t)s
				      andStart:(uint64_t)st
				     andNumber:(uint64_t)n
{
    int block = DEFAULT_PARTITION_BLOCK;
    uint64_t size = s / block;
    uint64_t t = n * block;
    Summary *ret = [Summary fineSummaryFromLogData:logData
					  forState:state
					  forVProc:vp
					  withSize:size
    					  andStart:st
    					 andNumber:t];


//    NSLog(@"fine summary has %qu pies, and should have %qu", r, t);
    ret = [ret coarsePartition:block group:state];


 //   NSLog(@"coarse summary has %qu pies and should have %qu", count, n);
    assert (n >= ret.pies.count);
    return ret;
}


+ (Summary *)coarseSummaryFromLogData:(LogData *)logData
			     forState:(StateGroup *)state
			     forVProc:(int32_t)vp
			     withSize:(uint64_t)s
			     andStart:(uint64_t)st
			    andNumber:(uint64_t)n
{
    Summary *sum = [Summary coarseSummaryFromLogDataPartition:logData
						     forState:state
						     forVProc:vp
						     withSize:s
						     andStart:st
						    andNumber:n];
    return sum;
}


STATIC_INLINE void pieInc(Pie *pie, uint64_t amt, uint64_t d, Detail *details)
{
    // NSLog(@"Incrementing pie %@ by amount %qu", pie, amt);
    int consumer_int = Detail_State_state(details[d]);
    NSNumber *consumer = [NSNumber numberWithInt:consumer_int];
    [pie incrementConsumer:consumer byAmount:amt];
}


///////////////////////////////////// UTILITIES for fineSummaryFromLogData /////////////////////////// {{{


int state_detail_end_before(Detail d, uint64_t t)
{
    event *e = Detail_State_end(d);
    return e ? Event_Time(*e) < t : 0;
}
uint64_t not_null_state_end_time(Detail d)
{
    event *e = Detail_State_end(d);
    if (!e)
    {
	[Exceptions raise:@"not_null_state_end_time: called on a detail with a null state start field"];
    }
    return Event_Time(*e);
}
uint64_t not_null_state_start_time(Detail d)
{
    event *e = Detail_State_start(d);
    if (!e)
    {
	[Exceptions raise:@"not_null_state_start_time: called on a detail with a null state start field"];
    }
    return Event_Time(*e);
}
int state_detail_start_before_eq(Detail d, uint64_t t)
{
    event *e = Detail_State_start(d);
    return e ? Event_Time(*e) <= t : 1;
}
int state_detail_end_after(Detail d, uint64_t t)
{
    event *e = Detail_State_end(d);
    return e ? Event_Time(*e) > t : 1;
}

///////////////////////////////////// END UTILITIES /////////////////////////// }}}

/// Common subroutine for reading data from log file
+ (Summary *)fineSummaryFromLogData:(LogData *)logData
			   forState:(StateGroup *)state
			   forVProc:(int32_t)vp
			   withSize:(uint64_t)size
			   andStart:(uint64_t)st
			  andNumber:(uint64_t)n
{
    VProc *vProc = [logData.vProcs objectAtIndex:vp];
    Detail *details = vProc.details;

    uint64_t t;
    uint64_t p;
    Pie *pie;
    NSMutableArray *pies;
    uint64_t d;




    // Initialize t, p, pie, pies, d to have the invariants listed below
    t = st;
    p = st;
    pie = [Pie emptyForStateGroup:state];

    Summary *ret = [[Summary alloc] initWithSize:size
					andStart:st
					andResource:state];
    pies = ret.pies;
    assert ( pies.count == 0);

    // initialize d to be the unique d which is the index of the detail containing st in its timespan
    d = 0;
    while (1)
    {
	if (d >= vProc.numDetails)
	{
	    [Exceptions raise:
	    @"Summary: fineSummaryFromLogData: no state details intersect the given start time"];
	}
	if ( state != Detail_Type(details[d]) )
	{
	    ++d;
	    continue;
	}
	if ( state_detail_start_before_eq(details[d], st) && state_detail_end_after(details[d], st))
	{
	    // d is now the correct index
	    break;
	}
	++d;
    }

    uint64_t i = 1;
    while (1)
    // Invariants
    // 0. pies contains all data corresponding to times < t
    // 1. pies contains no data corresponding to times >= t
    // 2. all time untill the next interesting event belongs to the consumer for detail d
    // 3. all pies corresponding to time intervals in (-inf, p) are finished and in pies
    // 4. pie is the unique pie corresponding to the time interval (p, p + size)
    // 5. no pies in the time interval (p + size, inf) have been created yet
    // 6. i = 1 + pies.count // the 1 is for pie
    {
	if ( state_detail_end_before(details[d], p + size) )//Event_Time(*Detail_State_end(details[d])) < p + size)
	// This test does not return true if d has no end
	// This test should not return true if d has no end.
	{
	    uint64_t old_d = d;
	    // new detail
	    while (1)
	    {
		++d;
		if (d >= vProc.numDetails)
		{
		    [Exceptions raise:
		    @"Summary: fineSummaryFromLogData: given interval exceeds the data in LogData"];
		}
		if ( state != Detail_Type(details[d]) )
		{
		    continue;
		}
		else // we have found the right d
		{
		    break;
		}
	    }

	    uint64_t k = not_null_state_start_time(details[d]);
	    pieInc(pie, k - t, old_d, details);
	    t = k;

	    /*
	    
	    uint64_t t2 = Event_Time(*Detail_State_start(details[d]));
	    assert (t == t2);

	    event *e = Detail_State_end(details[d]);
	    if (e == NULL)
	    {
		// Final
		pieInc(pie, p + size - t, d, details);
		[pie divideBy:size];
		[pie assertStochastic];
		[pies addObject:pie];
		
		return ret;
	    }
	    else
	    {
		pieInc(pie,  Event_Time(*e) - t, d, details);
	    }
	    */
	}
	else if (i == n)
	{
	    // Final
	    pieInc(pie, p + size - t, d, details);

	    // finish up the last pie
	    [pie divideBy:size];
	    [pie assertStochastic];
	    [pies addObject:pie];

	    return ret;
	}
	else { // assert ( p + size < Event_Time(*Detail_State_end(details[d])));
	    // new pie
	    pieInc(pie, p + size - t, d, details);
	    ++i;
	    [pie divideBy:size];
	    [pie assertStochastic];
	    [pies addObject:pie];
	    pie = [Pie emptyForStateGroup:state];
	    t = p = p + size;
	}
    }
}


// Common subroutine for reading data from log file
// This function has bugs, so it is being rewritten above
+ (Summary *)oldFineSummaryFromLogData:(LogData *)logData
			   forState:(StateGroup *)state
			   forVProc:(int32_t)vp
			   withSize:(uint64_t)size
			   andStart:(uint64_t)st
			  andNumber:(uint64_t)n
{
    Summary *ret = [[Summary alloc] initWithSize:size
					andStart:st
				     andResource:state];
    NSMutableArray *arr = ret.pies;
    assert (arr.count == 0);

    DetailEnumerator *d = [[DetailEnumerator alloc] initWithLogData:logData
							   andVProc:vp
							   andGroup:state];
    uint64_t p = st;
    // Make the first pie
    Pie *pie = [Pie emptyForStateGroup:state];

    for (Detail detail = d.next; (detail != NULL) && (arr.count < n); detail = d.next)
    {
	//NSLog(@"summary: examining new detail to put into pies");
        uint64_t start, end;
	event *start_event = Detail_State_start(detail);
	event *end_event = Detail_State_end(detail);
        start = start_event == NULL ? logData.firstTime : Event_Time(*start_event);
        end = end_event == NULL ? logData.lastTime : Event_Time(*end_event);

	// Sanity checks
	{

	if (! ( start <= end ) )
	{
	    NSLog(@"start <= end has failed start = %qu, end = %qu", start, end);
	    if (start == st) NSLog(@"start == st");
	    if (end == st + size * n) NSLog(@"end == st + size * n");
	    assert (start <= end);
	}
	// Skip events that lie outside the given interval (st, st + n * size)
	if ( end < st || st + n * size < start)
	{
	    continue;
	}
	
	// XXX correct?!
	if (start < p) start = p;
	
	
	if (! (p <= start))
	{
	    NSLog(@"p <= start has failed: p = %qu, start = %qu start event %x end event %x", p, start, start_event, end_event);
	    assert (p <= start && start <= p + size);
	}
	if (! (start <= p + size))
	{
	    NSLog(@"start <= p + size has failed: p = %qu, start = %qu", p, start);
	    assert (p <= start && start <= p + size);
	}
	if (! (end > p))
	{
	    NSLog(@"end = %qu, p = %qu, failing", end, p);
	    assert (end > p);
	}
	
	}
	
	//NSLog(@"Passed time tests");

        int consumer_int = Detail_State_state(detail);
        NSNumber *consumer = [NSNumber numberWithInt:consumer_int];

        if (end < p + size)
        {
	   // NSLog(@"summary: incrementing counter");
	   [pie incrementConsumer:consumer byAmount:end - start];
        }
        else // ( end >= p + size )
        {
	   // Finish this pie
    	   [pie incrementConsumer:consumer byAmount:p + size - start];
    	   [pie divideBy:size];
    	   [pie assertStochastic];
    	   [arr addObject:pie];
	    if (arr.count == n) return ret;
	 //   NSLog(@"adding pie to array");

    	   // Start the next pie
    	   while ( end >= p + size)
	   {
	       p += size;
	       pie = [Pie emptyForStateGroup:state];
	       [pie incrementConsumer:consumer byAmount:size];
	       [pie divideBy:size];
	       [pie assertStochastic];
	   //    NSLog(@"adding pie to array, pie has a single slice");
	       [arr addObject:pie];
	       if (arr.count == n) return ret;
	   }
    	   pie = [Pie emptyForStateGroup:state];
    	   [pie incrementConsumer:consumer byAmount:end - p];
        }
    }

  //  NSLog(@"fine summary allocated with array of pies %@", ret.pies);
    assert (ret.pies.count <= n);
    return ret;
}




@end


// OLD CODE SECTION
/* pies is
	// Fill the pie 
	while (1)
	{
	    int consumer_int = Detail_State_state(d.detail);
	    NSNumber *consumer = [NSNumber numberWithInt:consumer_int];
	    if (b >= p + size)
	    {
		[pie incrementConsumer:consumer byAmount:p + size - a];
		p += size;
		a = p;
		// b = b;  logically relevant, but computationally unneccessary
		break;
	    }
	    else // ( b < p + size )
	    {
		[pie incrementConsumer:consumer byAmount:b - a];

		tmp = b;
		NSNumber *tmp2 = d.next;
		if (tmp2 == NULL) return ret;
		b = tmp2.unsignedLongLongValue;

		a = tmp;
		continue;
	    }
	}

	// Insert the pie
	[pie divideBy:size];
	[pie assertStochastic];
	[arr addObject:pie];
    }




    return ret;
}
*/


