(* runtime-constants-sig.sml
 * 
 * COPYRIGHT (c) 2007 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 *
 * Information about the target architecture, operating system, and
 * runtime-system data structures.
 *)

signature RUNTIME_CONSTANTS =
  sig

    val wordSzB : IntInf.int		 (* number of bytes in a pointer-sized word *)
    val wordAlignB : IntInf.int	         (* byte alignment of pointers *)
    val boolSzB : IntInf.int		 (* size of boolean values in bytes *)
    val extendedAlignB : IntInf.int      (* alignment constraint for extended-precision
					  * floats *)

    val spillAreaSzB : IntInf.int     (* size of the spill area on the stack *)
    val spillAreaOffB : IntInf.int     (* offset from frame pointer to spill area *)
    val maxObjectSzB : IntInf.int     (* maximum number of bytes allowable in a
				       * heap-allocated object *) 

  (* magic number used to check consistency between generated code and the runtime system *)
    val magic : IntInf.int

  (* offsets into the VProc_t structure *)
    val atomic : IntInf.int
    val sigPending : IntInf.int
    val actionStk : IntInf.int
    val rdyQHd : IntInf.int
    val rdyQTl : IntInf.int
    val sndQHd : IntInf.int
    val sndQTl : IntInf.int
    val stdArg : IntInf.int 
    val stdEnvPtr : IntInf.int
    val stdCont : IntInf.int
    val stdExnCont : IntInf.int
    val allocPtr : IntInf.int
    val limitPtr : IntInf.int
    val globNextW : IntInf.int
    val globLimit : IntInf.int
    val eventId : IntInf.int

  (* mask to get address of VProc from allocation pointer *)
    val vpMask : IntInf.int

  end (* RUNTIME_CONSTANTS *)
