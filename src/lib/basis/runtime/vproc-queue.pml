(* vproc-queue.pml
 *
 * COPYRIGHT (c) 2009 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 *
 * This module contains functions for VProc thread queues. Each VProc owns a single 
 * queue, and access to the queue is restricted to certain patterns. A VProc can
 * only dequeue from its own queue, but can enqueue on either its own queue or a
 * remote queue.
 *
 * VProc queues consist of three linked lists: the primary and secondary lists and the
 * landing pad. We can dequeue locally on the primary list, enqueue locally on
 * the secondary list, and enqueue remotely on the landing pad.
 *)

structure VProcQueue (* :
  sig

    _prim(

    (**** Predicates ****)

    (* returns true if the local queue is empty *)
      define @is-local-queue-empty-in-atomic (self : vproc) : bool;
    (* returns true if the local queue contains more than one thread *)
      define @more-than-one-in-atomic (vp : vproc) : bool;

    (**** Local-queue operations ****)

    (* enqueue on the host's vproc's thread queue *)
      define inline @enqueue-in-atomic (vp : vproc, fls : FLS.fls, fiber : PT.fiber) : ();
      define inline @enqueue (fls : FLS.fls, fiber : PT.fiber) : ();
      define inline @secondary-enqueue-in-atomic (vp : vproc, fls : FLS.fls, fiber : PT.fiber) : ();
      define inline @secondary-enqueue (fls : FLS.fls, fiber : PT.fiber) : ();
    (* dequeue from the local queue  *)
      define inline @dequeue-in-atomic () : O.option;
    (* dequeue the first item to satisfy the given predicate  *)
      define @dequeue-with-pred-in-atomic (f : fun(FLS.fls / exh -> bool) / exh : exh) : O.option;

    (**** Remote-queue operations ****)

    (* poll the landing pad for threads. if there are threads, we move them to the local thread queue
     * and return true. otherwise we return false.
     *)
      define inline @poll-landing-pad-in-atomic (vp : vproc) : bool:
    (* enqueue on a given vproc *)
      define @enqueue-on-vproc-in-atomic (self : vproc, dst : vproc, fls : FLS.fls, k : PT.fiber) : ();
    (* enqueue on a remote vproc *)
      define @enqueue-on-vproc (dst : vproc, fls : FLS.fls, k : PT.fiber) : ();

    )

  end *) = struct

    structure PT = PrimTypes
    structure O = Option

#include "vproc-queue.def"

    _primcode (

    (**** Predicates ****)

    (* returns true if the local queue is empty *)
      define @primary-is-local-queue-empty-in-atomic (self : vproc) : bool =
	  let tl : queue_item = vpload (VP_RDYQ_TL, self)
	  if Equal(tl, Q_EMPTY) then
	      let hd : queue_item = vpload (VP_RDYQ_HD, self)
	      (* in *)
		if Equal(hd, Q_EMPTY)
		  then return (true)
		  else return (false)
	    else return (false)
	;

    (* returns true if the secondary vproc queue is empty *)
      define @secondary-is-local-queue-empty-in-atomic (self : vproc) : bool =
	  let tl : queue_item = vpload (VP_SNDQ_TL, self)
	  if Equal(tl, Q_EMPTY) then
	      let hd : queue_item = vpload (VP_SNDQ_HD, self)
	      (* in *)
		if Equal(hd, Q_EMPTY)
		  then return (true)
		  else return (false)
	    else return (false)
	;

    (* returns true if both queues are empty *)
      define @is-local-queue-empty-in-atomic (self : vproc) : bool =
      	let v : bool = @primary-is-local-queue-empty-in-atomic(self)
	let w : bool = @secondary-is-local-queue-empty-in-atomic(self)
	if (v) then return(w)
	else return (false)
	;

    (* returns true if the local queue contains more than one thread *)
      define @primary-more-than-one-in-atomic (vp : vproc) : bool =
	  let tl : queue_item = vpload (VP_RDYQ_TL, vp)
	  let hd : queue_item = vpload (VP_RDYQ_HD, vp)
	  let nTl : int =
		if Equal(tl, Q_EMPTY) then return(0)
		else if Equal(SELECT(LINK_OFF, tl), Q_EMPTY) then return (1)
		else return(2)
	  let nHd : int =
		if Equal(hd, Q_EMPTY) then return(0)
		else if Equal(SELECT(LINK_OFF, hd), Q_EMPTY) then return (1)
		else return(2)
	  if I32Gt(I32Add(nTl, nHd), 1) then return(true) else return(false)
	;

    (* returns true if the local queue contains more than one thread *)
      define @secondary-more-than-one-in-atomic (vp : vproc) : bool =
	  let tl : queue_item = vpload (VP_SNDQ_TL, vp)
	  let hd : queue_item = vpload (VP_SNDQ_HD, vp)
	  let nTl : int =
		if Equal(tl, Q_EMPTY) then return(0)
		else if Equal(SELECT(LINK_OFF, tl), Q_EMPTY) then return (1)
		else return(2)
	  let nHd : int =
		if Equal(hd, Q_EMPTY) then return(0)
		else if Equal(SELECT(LINK_OFF, hd), Q_EMPTY) then return (1)
		else return(2)
	  if I32Gt(I32Add(nTl, nHd), 1) then return(true) else return(false)
	;

    (* returns true if between both queues, there are at least two threads *)
      define @more-than-one-in-atomic (self : vproc) : bool =
      	let v : bool = @primary-more-than-one-in-atomic(self)
	let w : bool = @secondary-more-than-one-in-atomic(self)
	if (v) then return(true)
	else
	  if (w) then return(true)
	  else
	    let a : bool = @primary-is-local-queue-empty-in-atomic(self)
	    let b : bool = @secondary-is-local-queue-empty-in-atomic(self)
	    if (a) then return(b)
	    else return(false)
	;

    (**** Local-queue operations ****)

    (* reverse a non-empty queue.
     *   - fls fiber-local storage component of the first item of the input queue
     *   - k fiber component of the first item of the input queue
     *   - rest the rest of the queue
     * i.e., @queue-reverse(fls, k, (fls', k', Q_EMPTY)) ==> (fls', k', (fls, k, Q_EMPTY))
     *)
      define @queue-reverse (fls : FLS.fls, k : PT.fiber, rest : queue_item) : queue_item =
	  fun revQueue (fls : FLS.fls, k : PT.fiber, rest : queue_item, acc : queue_item) : queue_item =
	       let acc : queue_item = alloc(fls, k, acc)
	       if Equal(rest, Q_EMPTY)
		 then return(acc)
		 else apply revQueue (SELECT(FLS_OFF, rest), SELECT(FIBER_OFF, rest), SELECT(LINK_OFF, rest), acc)
	  let qitem : queue_item = apply revQueue (fls, k, rest, Q_EMPTY)
	  return (qitem)
	;

      define @queue-append (queue1 : queue_item, queue2 : queue_item) : queue_item =
	  fun append (queue1 : queue_item) : queue_item =
	      if Equal(queue1, Q_EMPTY)
		then return(queue2)
		else 
		  let rest : queue_item = apply append(SELECT(LINK_OFF, queue1))
		  let queue11 : queue_item = alloc(SELECT(FLS_OFF, queue1), SELECT(FIBER_OFF, queue1), rest)
		  return(queue11)
	  apply append (queue1)
      ;

    (* dequeue from the local queue  *)
      define inline @primary-dequeue-in-atomic (vp : vproc) : O.option =
	  let hd : queue_item = vpload (VP_RDYQ_HD, vp)	  
          if NotEqual(hd, Q_EMPTY) then
	    (* got a thread from the primary list *)
	      do vpstore (VP_RDYQ_HD, vp, SELECT(LINK_OFF, hd))
	      return (O.SOME (hd))
	  else
	      let tl : queue_item = vpload (VP_RDYQ_TL, vp)
	      if NotEqual(tl, Q_EMPTY) then
		(* got a thread from the secondary list *)
		  do vpstore (VP_RDYQ_TL, vp, Q_EMPTY)
		  let qitem : queue_item = @queue-reverse (SELECT(FLS_OFF, tl), 
							   SELECT(FIBER_OFF, tl), 
							   (queue_item)SELECT(LINK_OFF, tl))
		  do vpstore (VP_RDYQ_HD, vp, (queue_item)SELECT(LINK_OFF, qitem))
		  return (O.SOME(qitem))
	      else
                  return (O.NONE)
	    ;

    (* dequeue from the secondary local queue  *)
      define inline @secondary-dequeue-in-atomic (vp : vproc) : O.option =
	  let hd : queue_item = vpload (VP_SNDQ_HD, vp)	  
          if NotEqual(hd, Q_EMPTY) then
	    (* got a thread from the primary list *)
	      do vpstore (VP_SNDQ_HD, vp, SELECT(LINK_OFF, hd))
	      return (O.SOME (hd))
	  else
	      let tl : queue_item = vpload (VP_SNDQ_TL, vp)
	      if NotEqual(tl, Q_EMPTY) then
		(* got a thread from the secondary list *)
		  do vpstore (VP_SNDQ_TL, vp, Q_EMPTY)
		  let qitem : queue_item = @queue-reverse (SELECT(FLS_OFF, tl), 
							   SELECT(FIBER_OFF, tl), 
							   (queue_item)SELECT(LINK_OFF, tl))
		  do vpstore (VP_SNDQ_HD, vp, (queue_item)SELECT(LINK_OFF, qitem))
		  return (O.SOME(qitem))
	      else
                  return (O.NONE)
	    ;

    (* dequeue from the first nonempty local queue available *)
      define inline @dequeue-in-atomic (vp : vproc) : O.option =
        let t : O.option = @primary-dequeue-in-atomic(vp)
	case t
	  of O.SOME(q : queue_item) => return (O.SOME(q))
	   | O.NONE =>
	     let p : O.option = @secondary-dequeue-in-atomic(vp)
	     return (p)
	end
	;

    (* enqueue on the local queue. NOTE: signals must be masked *)
      define inline @enqueue-in-atomic (vp : vproc, fls : FLS.fls, fiber : PT.fiber) : () =
	  let tl : queue_item = vpload (VP_RDYQ_TL, vp)
	  let qitem : queue_item = alloc(fls, fiber, tl)
	  do vpstore (VP_RDYQ_TL, vp, qitem)
	  return () 
	;

    (* enqueue on the secondary local queue. NOTE: signals must be masked *)
      define inline @secondary-enqueue-in-atomic (vp : vproc, fls : FLS.fls, fiber : PT.fiber) : () =
	  let tl : queue_item = vpload (VP_SNDQ_TL, vp)
	  let qitem : queue_item = alloc(fls, fiber, tl)
	  do vpstore (VP_SNDQ_TL, vp, qitem)
	  return () 
	;

    (* enqueue on the host's vproc's thread queue *)
      define inline @enqueue (fls : FLS.fls, fiber : PT.fiber) : () =
	  let vp : vproc = SchedulerAction.@atomic-begin()
	  do @enqueue-in-atomic (vp, fls, fiber)
	  do SchedulerAction.@atomic-end(vp)
	  return ()
	;

    (* enqueue on the host's vproc's secondary thread queue *)
      define inline @secondary-enqueue (fls : FLS.fls, fiber : PT.fiber) : () =
	  let vp : vproc = SchedulerAction.@atomic-begin()
	  do @secondary-enqueue-in-atomic (vp, fls, fiber)
	  do SchedulerAction.@atomic-end(vp)
	  return ()
	;

    (* dequeue the first item to satisfy the given predicate  *)
      define @primary-dequeue-with-pred-in-atomic (self : vproc, f : fun(FLS.fls / exh -> bool) / exh : exh) : O.option =
	  cont exit (x : O.option) = return(x)
	  let qitem : O.option = @dequeue-in-atomic(self)
	  case qitem
	   of O.NONE => throw exit(O.NONE)
	    | O.SOME (origItem : queue_item) =>
	      fun lp () : O.option =
		  let qitem : O.option = @dequeue-in-atomic(self)
		  case qitem
		   of O.NONE => throw exit(O.NONE)
		    | O.SOME(item : queue_item) =>
		      let b : bool = apply f (SELECT(FLS_OFF, item) / exh)
		      case b
		       of true => throw exit (O.SOME(item))
			| false =>
			    if Equal(SELECT(FLS_OFF, item), SELECT(FLS_OFF, origItem))
			      then 
				do @enqueue-in-atomic(self, SELECT(FLS_OFF, item), SELECT(FIBER_OFF, item))
				throw exit (O.NONE)
			      else 
				do @enqueue-in-atomic(self, SELECT(FLS_OFF, item), SELECT(FIBER_OFF, item))
				apply lp()
		      end
		  end
	      let b : bool = apply f (SELECT(FLS_OFF, origItem) / exh)
		case b
		 of true => throw exit(O.SOME(origItem))
		  | false =>
		      do @enqueue-in-atomic(self, SELECT(FLS_OFF, origItem), SELECT(FIBER_OFF, origItem))
		      apply lp()
		end
	  end
	;

    (* dequeue the first item to satisfy the given predicate  *)
      define @secondary-dequeue-with-pred-in-atomic (self : vproc, f : fun(FLS.fls / exh -> bool) / exh : exh) : O.option =
	  cont exit (x : O.option) = return(x)
	  let qitem : O.option = @secondary-dequeue-in-atomic(self)
	  case qitem
	   of O.NONE => throw exit(O.NONE)
	    | O.SOME (origItem : queue_item) =>
	      fun lp () : O.option =
		  let qitem : O.option = @secondary-dequeue-in-atomic(self)
		  case qitem
		   of O.NONE => throw exit(O.NONE)
		    | O.SOME(item : queue_item) =>
		      let b : bool = apply f (SELECT(FLS_OFF, item) / exh)
		      case b
		       of true => throw exit (O.SOME(item))
			| false =>
			    if Equal(SELECT(FLS_OFF, item), SELECT(FLS_OFF, origItem))
			      then 
				do @secondary-enqueue-in-atomic(self, SELECT(FLS_OFF, item), SELECT(FIBER_OFF, item))
				throw exit (O.NONE)
			      else 
				do @secondary-enqueue-in-atomic(self, SELECT(FLS_OFF, item), SELECT(FIBER_OFF, item))
				apply lp()
		      end
		  end
	      let b : bool = apply f (SELECT(FLS_OFF, origItem) / exh)
		case b
		 of true => throw exit(O.SOME(origItem))
		  | false =>
		      do @secondary-enqueue-in-atomic(self, SELECT(FLS_OFF, origItem), SELECT(FIBER_OFF, origItem))
		      apply lp()
		end
	  end
	;

    (* dequeue from the first nonempty local queue available, with the given predicate *)
      define @dequeue-with-pred-in-atomic (self : vproc, f : fun(FLS.fls / exh -> bool) / exh : exh) : O.option =
        let t : O.option = @primary-dequeue-with-pred-in-atomic(self,f / exh)
	case t
	  of O.SOME(q : queue_item) => return (O.SOME(q))
	   | O.NONE =>
	     let p : O.option = @secondary-dequeue-with-pred-in-atomic(self, f / exh)
	     return (p)
	end
	;

    (**** Remote-queue operations ****)

    (* poll the landing pad for threads. if there are threads, we move them to the local thread queue
     * and return true. otherwise we return false.
     *)
      define inline @poll-landing-pad-in-atomic (vp : vproc) : bool =
	  let landingPadItems : queue_item = VProc.@recv-in-atomic(vp)
	  if Equal (landingPadItems, Q_EMPTY) then
	      return (false)
	  else
	      let hd : queue_item = vpload (VP_RDYQ_HD, vp)
	      let newHd : queue_item = @queue-append (landingPadItems, hd)
	      do vpstore (VP_RDYQ_HD, vp, newHd)
	      return (true)
	;

    (* enqueue on a given vproc. NOTE: signals must be masked  *)
      define inline @enqueue-on-vproc-in-atomic (self : vproc, dst : vproc, fls : FLS.fls, k : PT.fiber) : () =
          if Equal(self, dst)
	    then @enqueue-in-atomic(self, fls, k)
	    else VProc.@send-in-atomic(self, dst, fls, k)
      ;

    (* enqueue on a remote vproc *)
      define inline @enqueue-on-vproc (dst : vproc, fls : FLS.fls, k : PT.fiber) : () =
	let self : vproc = SchedulerAction.@atomic-begin()
	do @enqueue-on-vproc-in-atomic(self, dst, fls, k)
	do SchedulerAction.@atomic-end(self)
	return()
      ;

    )

  end
