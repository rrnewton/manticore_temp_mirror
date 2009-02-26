(* future-sig.pml
 *
 * COPYRIGHT (c) 2008 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 *
 * Generic interface for futures.
 *)

signature FUTURE =
  sig

    type 'a thunk = unit -> 'a
    type 'a future

  (* future creation. the second argument specifies whether the future is cancelable. *)
    val future : ('a thunk * bool) -> 'a future

  (* synchronize on the completion of a future *)
    val touch : 'a future -> 'a

  (* cancel the evaluation of a future. 
   * POSTCONDITION: The future is cleared from the ready queue. Any subsequent touches on this future
   * or its children retuls in undefined behavior.
   *)
    val cancel : 'a future -> unit

  end
