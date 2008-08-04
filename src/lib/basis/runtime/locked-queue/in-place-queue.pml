(* in-place-queue.pml
 *
 * COPYRIGHT (c) 2008 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 *
 * In place queue operations.
 *)

#define ELT_HD_OFF    0
#define ELT_TL_OFF    1

structure InPlaceQueue =
  struct

    structure PT = PrimTypes
    structure FLS = FiberLocalStorage

    _primcode (

    (* queue elements; item, pointer to the next element *)
      typedef elt = ![any, any];

    (* lock, head, tail, blocked fiber head, blocked fiber tail *)
      typedef queue = ![PT.bool, elt, elt, elt, elt];

    (* thread blocked on a dequeue: continuation expecting the dequeue value, fiber-local storage and the
     * vproc where the thread blocked.
     *)
      typedef blocked_thread = [cont(any), FLS.fls, vproc];

      define @enqueue (q : queue, qElt : elt / exh : PT.exh) : () =                   
        let qHd : elt = SELECT(HD_OFF, q)
        let qTl : elt = SELECT(TL_OFF, q) 						  
        do if Equal (qTl, EMPTY)                                                                 
              then return ()                                                                                  
           else let qElt : any = (any)qElt      								  
                 do UPDATE(ELT_TL_OFF, qTl, qElt) 						  
	         return () 			    							  
        do UPDATE(TL_OFF, q, qElt)       	     	    	  				          
        if Equal (qHd, EMPTY)  								  
	   then (* the queue was empty *) 									  
            do UPDATE(HD_OFF, q, qElt) 								  
            return () 		    									  
	else return () 											  
      ;    	  	 											  
													  
      define @dequeue (q : queue  / exh : PT.exh) : Option.option = 		  
        let qTl : elt = SELECT(TL_OFF, q)        	 	     	   	     		  
        let qHd : elt = SELECT(HD_OFF, q) 						  
        if Equal (qHd, EMPTY) 		     							  
           then (* the queue is empty *) 									  
                return(NONE)
	else (* the queue is nonempty, so take an element off the queue head *) 				  
          let qNext : any = SELECT(ELT_TL_OFF, qHd) 	     	  				  
          let qNext : elt = (elt)qNext 					  
          do if Equal (qHd, qTl) 	   								  
                then (* there is one element on the queue, so clear out the tail *) 			  
                     let emptyQ : elt = (elt)EMPTY 	  
                     do UPDATE(TL_OFF, q, emptyQ) 							  
                     return () 		       								  
                else return () 										  
          do UPDATE(HD_OFF, q, qNext) 								  
          let elt : any = SELECT(ELT_HD_OFF, qHd) 						  
          return(Option.SOME(elt))
      ;

    )

  end
