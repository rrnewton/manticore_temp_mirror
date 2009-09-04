/** \file  EventInfoController.h
 * \author Korei Klein
 * \date 8/7/09
 *
 */

#import <Cocoa/Cocoa.h>
#import "EventArg.h"
#import "Detail.h"
#import "EventInfoView.h"
struct LogFileDesc;
struct EventDesc;

/** Controller object for EventInfoView
 *  Causes an EventInfoView to display infomation about a single event
 */
@interface EventInfoController : NSViewController {
    IBOutlet EventInfoView *eiv; ///< The view

    struct LogFileDesc *logDesc;

    /// This table will hold the arguments to the event being displayed
    IBOutlet NSTableView *table;

    /// The event to display
    event *value;
    /// The description of the event to display
    struct EventDesc *eventDesc;

    NSString *name; ///< the name of the event to display
    /// This array contains EventArg, the arguments to the event being displayed
    NSMutableArray *args;
    /// The description of the event to be displayed
    NSString *description;

    /// The time at which the event to be displayed took place (in string format)
    NSString *time;
}

/// Initialize
- (EventInfoController *)initWithNibName:(NSString *)n
				    bundle:(NSBundle *)b
				   logDesc:(struct LogFileDesc *)logDescVal;


@property (readonly) EventInfoView *eiv;

@property (readwrite, assign) NSString *time;


@property (readwrite, assign) event *value;
@property (readwrite, assign) NSString *name;
@property (readwrite, assign) NSString *description;
@property (readwrite, assign) NSArray *args;

@end
