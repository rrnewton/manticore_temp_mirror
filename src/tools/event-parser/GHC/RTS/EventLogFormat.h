/* -----------------------------------------------------------------------------
 *
 * (c) The GHC Team, 2008-2009
 *
 * Event log format
 * 
 * The log format is designed to be extensible: old tools should be
 * able to parse (but not necessarily understand all of) new versions
 * of the format, and new tools will be able to understand old log
 * files.
 * 
 * Each event has a specific format.  If you add new events, give them
 * new numbers: we never re-use old event numbers.
 *
 * - The format is endian-independent: all values are represented in 
 *    bigendian order.
 *
 * - The format is extensible:
 *
 *    - The header describes each event type and its length.  Tools
 *      that don't recognise a particular event type can skip those events.
 *
 *    - There is room for extra information in the event type
 *      specification, which can be ignored by older tools.
 *
 *    - Events can have extra information added, but existing fields
 *      cannot be changed.  Tools should ignore extra fields at the
 *      end of the event record.
 *
 *    - Old event type ids are never re-used; just take a new identifier.
 *
 *
 * The format
 * ----------
 *
 * log : EVENT_HEADER_BEGIN
 *       EventType*
 *       EVENT_HEADER_END
 *       EVENT_DATA_BEGIN
 *       Event*
 *       EVENT_DATA_END
 *
 * EventType :
 *       EVENT_ET_BEGIN
 *       Word16         -- unique identifier for this event
 *       Int16          -- >=0  size of the event in bytes (minus the header)
 *                      -- -1   variable size
 *       Word32         -- length of the next field in bytes
 *       Word8*         -- string describing the event
 *       Word32         -- length of the next field in bytes
 *       Word8*         -- extra info (for future extensions)
 *       EVENT_ET_END
 *
 * Event : 
 *       Word16         -- event_type
 *       Word64         -- time (nanosecs)
 *       [Word16]       -- length of the rest (for variable-sized events only)
 *       ... extra event-specific info ...
 *
 *
 * To add a new event
 * ------------------
 *
 *  - In this file:
 *    - give it a new number, add a new #define EVENT_XXX below
 *  - In EventLog.c
 *    - add it to the EventDesc array
 *    - emit the event type in initEventLogging()
 *    - emit the new event in postEvent_()
 *    - generate the event itself by calling postEvent() somewhere
 *  - In the Haskell code to parse the event log file:
 *    - add types and code to read the new event
 *
 * -------------------------------------------------------------------------- */

#ifndef RTS_EVENTLOGFORMAT_H
#define RTS_EVENTLOGFORMAT_H

/*
 * Markers for begin/end of the Header.
 */
#define EVENT_HEADER_BEGIN    0x68647262 /* 'h' 'd' 'r' 'b' */
#define EVENT_HEADER_END      0x68647265 /* 'h' 'd' 'r' 'e' */

#define EVENT_DATA_BEGIN      0x64617462 /* 'd' 'a' 't' 'b' */
#define EVENT_DATA_END        0xffff

/*
 * Markers for begin/end of the list of Event Types in the Header.
 * Header, Event Type, Begin = hetb
 * Header, Event Type, End = hete
 */
#define EVENT_HET_BEGIN       0x68657462 /* 'h' 'e' 't' 'b' */
#define EVENT_HET_END         0x68657465 /* 'h' 'e' 't' 'e' */

#define EVENT_ET_BEGIN        0x65746200 /* 'e' 't' 'b' 0 */
#define EVENT_ET_END          0x65746500 /* 'e' 't' 'e' 0 */

/*
 * Types of event
 */
/*No EVENT_MINOR_GC, EVENT_GC_START implies a minor GC*/

#define VPROCSTARTIDLE 1
#define STARTUP 2
#define VPROCSTART 3
#define VPROCEXIT 4
#define VPROCEXITMAIN 5
#define VPROCIDLE 6
#define VPROCSLEEP 7
#define VPROCWAKEUP 8
#define PREEMPTVPROC 9
#define PREEMPTSIGNAL 10
#define GCSIGNAL 11
#define MINORGCSTART 12
#define MINORGCEND 13
#define STARTGC 14
#define ENDGC 15
#define MAJORGCSTART 16
#define MAJORGCEND 17
#define RUNTHREAD 18
#define STOPTHREAD 19
#define GLOBALGCINIT 20
#define GLOBALGCEND 21
#define GLOBALGCVPSTART 22
#define GLOBALGCVPDONE 23
#define PROMOTESTART 24
#define PROMOTEEND 25
#define THDSPAWN 26
#define THDSPAWNON 27
#define THDSTART 28
#define THDEXIT 29
#define MSGSENDOFFERED 30
#define MSGSENDRESUMED 31
#define MSGRECV 32
#define MSGRECVOFFERED 33
#define MSGRECVRESUMED 34
#define MSGSEND 35
#define WSINIT 36
#define WSTERMINATE 37
#define WSWORKERINIT 38
#define WSEXECUTE 39
#define WSPREEMPTED 40
#define WSTHIEFSEND 41
#define WSTHIEFBEGIN 42
#define WSTHIEFEND 43
#define WSTHIEFSUCCESSFUL 44
#define WSTHIEFUNSUCCESSFUL 45
#define WSSLEEP 46
#define ROPEREBALANCEBEGIN 47
#define ROPEREBALANCEEND 48
#define EVENTBLOCK 49
#define NUM_GHC_EVENT_TAGS 50



#endif /* RTS_EVENTLOGFORMAT_H */
