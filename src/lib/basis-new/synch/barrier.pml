(* barrier.pml
 *
 * COPYRIGHT (c) 2008 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 *
 * Barriers.
 *)

structure Barrier =
  struct

    _primcode(

#define NUM_IN_BARRIER_OFF    0
#define BARRIER_COUNT_OFF     1

      typedef barrier = ![
                int,         (* number of fibers that are part of the barrier *)
		int          (* count of ready fibers *)
              ];

      define @new (n : int    (* number of fibers *)
		  / exh : exh) : barrier =
	let barrier : barrier = alloc(n, 0)
	let barrier : barrier = promote(barrier)
	return(barrier)
      ;

    (* one more participant is ready to pass through the barrier *)
      define @ready (b : barrier / exh : exh) : () =
	let x : int = I32FetchAndAdd (&BARRIER_COUNT_OFF(b), 1)
	return()
      ;

    (* synchronize participating fibers waiting on the barrier *)
      define @wait (b : barrier / exh : exh) : () =
        let vp : vproc = SchedulerAction.@atomic-begin()
        fun barrierSpin () : () =	
	      if I32Eq(SELECT(NUM_IN_BARRIER_OFF, b), SELECT(BARRIER_COUNT_OFF, b))
		 then SchedulerAction.@atomic-end(vp)
	      else 
		  do Pause()
		  apply barrierSpin()
	apply barrierSpin ()
      ;
    )

  end
