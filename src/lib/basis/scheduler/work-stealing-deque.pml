(* work-stealing-deque.pml
 *
 * COPYRIGHT (c) 2009 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 *
 * Deque structure used by the Work Stealing scheduler. 
 *
 * Memory management:
 * Since we allocate deques in the C heap, we rely on a reference counting scheme to manage memory
 * associated with deques. We maintain reference counts as follows. The reference count of
 * a newly-created deque is set to 1 (by @new-in-atomic). Reference counts are incremented
 * for each deque returned by the call to @local-deques-in-atomic. Reference counts are decremented
 * by @release-in-atomic and @release-deques-in-atomic. The garbage collector frees deques that
 * are both empty and have a reference count of zero.
 *
 *)

structure WorkStealingDeque (* :
  sig

    _prim (

      typedef deque;

    (* the second argument is the number of elements. the new deque is automatically claimed for the
     * calling process.
     *)
      define inline @new-primary-deque-in-atomic (self : vproc, workerId : UID.uid, size : int) : deque;
      define inline @new-secondary-deque-in-atomic (self : vproc, workerId : UID.uid, size : int) : deque;
      define inline @new-resume-deque-in-atomic (self : vproc, workerId : UID.uid, size : int) : deque;

      define inline @is-full-in-atomic (self : vproc, deque : deque) : bool;
      define inline @is-empty-in-atomic (self : vproc, deque : deque) : bool;
      define inline @is-claimed-in-atomic (self : vproc, deque : deque) : bool;
    (* returns the number of elements contained in the deque *)
      define inline @size (deque : deque) : int;

      define inline @push-new-end-in-atomic (self : vproc, deque : deque, elt : any) : ();
      define inline @pop-new-end-in-atomic (self : vproc, deque : deque) : Option.option;
      define inline @pop-old-end-in-atomic (self : vproc, deque : deque) : Option.option;

    (* returns the primary deque associated with the given vproc and the work group id. all the deques in this list are 
     * automatically claimed for the caller. *)
      define @primary-deque-in-atomic (self : vproc, workGroupId : ImplicitThread.work_group_id) : Option.option;

    (* returns the secondary deque associated with the given vproc and the work group id. all the deques in this list are 
     * automatically claimed for the caller. *)
      define @secondary-deque-in-atomic (self : vproc, workGroupId : ImplicitThread.work_group_id) : Option.option;

    (* returns all nonempty resume deques associated with the given vproc and the work group id. all the deques in this list are 
     * automatically claimed for the caller. *)
      define @resume-deques-in-atomic (self : vproc, workGroupId : ImplicitThread.work_group_id) : (* [deque] *) List.list;

      define inline @release-in-atomic (self : vproc, deque : deque) : ();
      define @release-deques-in-atomic (self : vproc, deques : List.list) : ();

    (* double the size of the deque *)
      define @double-size-in-atomic (self : vproc, workGroupId : ImplicitThread.work_group_id, deque : deque) : deque;

    (* the list of returned threads is ordered from oldest to youngest *)
      define @to-list-in-atomic (self : vproc, deque : D.deque) : (* ImplicitThread.thread *) List.list;
    (* the list of threads is inserted at the new end of the deque *)
      define @add-list-in-atomic (self : vproc, deque : D.deque, thds : List.list) : ();

    )

  end *) = struct

#define DEQUE_NIL_ELT        enum(0):any

    _primcode (

      extern void *GetNthVProc (int) __attribute__((pure));
      extern void *M_PrimaryDequeAlloc (void *, long, int);
      extern void *M_SecondaryDequeAlloc (void *, long, int);
      extern void *M_ResumeDequeAlloc (void *, long, int);
      extern void *M_PrimaryDeque (void *, long);
      extern void *M_SecondaryDeque (void *, long);
      extern void *M_ResumeDeques (void *, long) __attribute__((alloc));
      extern void M_AssertDequeAddr (void *, int, void *);

    (* Deque representation:
     *
     * For compactness, we represent deques as circular buffers. There are two pointers into this buffer:
     * "old" and "new". The old pointer points to the oldest element on the deque and new points to the 
     * newest. Our convention is that old points to the leftmost element and new points to the rightmost
     * element. In other words, elements increase in age going from right to left.
     *
     * To distinguish whether the deque is empty or full, we always keep one deque entry open, which means
     * that we waste a word of memory for each deque. 
     *
     *)

    (* the type deque has the byte layout corresponding to the C struct below *)
    (*

	struct Deque_s {
	    int32_t       old;           // pointer to the oldest element in the deque
	    int32_t       new;           // pointer to the address immediately to the right of the newest element
	    int32_t       maxSz;         // max number of elements
            int32_t       nClaimed;      // the number of processes that hold a reference to the deque
	    Value_t       elts[];        // elements of the deque
	};

    *)

    )

#define DEQUE_OLD_OFFB        0
#define DEQUE_NEW_OFFB        4
#define DEQUE_MAXSZ_OFFB      8
#define DEQUE_NCLAIMED_OFFB   12
#define DEQUE_ELTS_OFFB       16

#define LOAD_DEQUE_OLD(deq)        AdrLoadI32 ((addr(int))&0(deq))
#define LOAD_DEQUE_NEW(deq)        AdrLoadI32 ((addr(int))AdrAddI64 (&0(deq), DEQUE_NEW_OFFB:long))
#define STORE_DEQUE_OLD(deq, i)    AdrStoreI32 ((addr(int))&0(deq), i)
#define STORE_DEQUE_NEW(deq, i)    AdrStoreI32 ((addr(int))AdrAddI64 (&0(deq), DEQUE_NEW_OFFB:long), i)

#define LOAD_DEQUE_MAX_SIZE(deq)   AdrLoadI32 ((addr(int))AdrAddI64 (&0(deq), DEQUE_MAXSZ_OFFB:long))

#define LOAD_DEQUE_NCLAIMED(deq)        AdrLoadI32 ((addr(int))AdrAddI64 (&0(deq), DEQUE_NCLAIMED_OFFB:long))
#define STORE_DEQUE_NCLAIMED(deq, c)    AdrStoreI32 ((addr(int))AdrAddI64 (&0(deq), DEQUE_NCLAIMED_OFFB:long), c)

      _primcode (

	define inline @size (deq : deque) : int =
	    if I32Lte (LOAD_DEQUE_OLD(deq), LOAD_DEQUE_NEW(deq)) then
		return (I32Sub (LOAD_DEQUE_NEW(deq), LOAD_DEQUE_OLD(deq)))
	    else (* wrapped around *)
		return (I32Add (I32Sub (LOAD_DEQUE_MAX_SIZE(deq), 
					LOAD_DEQUE_OLD(deq)), 
				LOAD_DEQUE_NEW(deq)))
	  ;

	define @assert-in-bounds (deq : deque, i : int) : () =
	    do assert(I32Gte (i, 0))
	    do assert(I32Lt (i, LOAD_DEQUE_MAX_SIZE(deq)))
	    if I32Lte (LOAD_DEQUE_OLD(deq), LOAD_DEQUE_NEW(deq)) then
		do assert(I32Gte (i, LOAD_DEQUE_OLD(deq)))
		do assert(I32Lt (i, LOAD_DEQUE_NEW(deq)))
  	        return ()
	    else
		if I32Gt (i, LOAD_DEQUE_NEW(deq)) then
		    do assert(I32Gte (i, LOAD_DEQUE_OLD(deq)))
		    return ()
		else if I32Eq (i, LOAD_DEQUE_NEW(deq)) then
		    do assert_fail()
		    return ()
		else
		    do assert(I32Lt (i, LOAD_DEQUE_NEW(deq)))
  	            return ()
	  ;

	define inline @assert-ptr (deq : deque, i : int) : () =
#ifndef NDEBUG
	    do ccall M_AssertDequeAddr (deq, i, AdrAddI64 (&0(deq), 
				   I64Add (DEQUE_ELTS_OFFB:long,         (* the byte offset of elts *)
					 I32ToI64X (I32LSh (i, 3)))))
#endif
	    return ()
	  ;

	define inline @update (deq : deque, i : int, elt : any) : () =
	    do @assert-in-bounds (deq, i)
            do @assert-ptr (deq, i)
	    do AdrStore (AdrAddI64 (&0(deq), 
				   I64Add (DEQUE_ELTS_OFFB:long,         (* the byte offset of elts *)
				   I32ToI64X (I32LSh (i, 3)))), 
			  elt)
	    return ()
	  ;

	define inline @sub (deq : deque, i : int) : any =
	    do @assert-in-bounds (deq, i)
            do @assert-ptr (deq, i)
	    let elt : any = AdrLoad (AdrAddI64 (&0(deq),         (* the byte offset of elts *)
					       I64Add (DEQUE_ELTS_OFFB:long,
					       I32ToI64X (I32LSh (i, 3)))))
	    return (elt)
	  ;

	(* check the deque for consistency *)
	define @check-deque (deq : deque) : () =
	    do assert(NotEqual(deq, DEQUE_NIL_ELT))
	    do assert(I32Gte (LOAD_DEQUE_NEW(deq), 0))
	    do assert(I32Gte (LOAD_DEQUE_OLD(deq), 0))
	    do assert(I32Lt (LOAD_DEQUE_NEW(deq), LOAD_DEQUE_MAX_SIZE(deq)))
	    do assert(I32Lt (LOAD_DEQUE_OLD(deq), LOAD_DEQUE_MAX_SIZE(deq)))
	    return ()
	  ;

      (* move the index i one position left w.r.t. the deque size sz *)
	define inline @move-left (i : int, sz : int) : int =
	    if I32Lte (i, 0) then
		return (I32Sub (sz, 1))
	    else
		return (I32Sub (i, 1))
	  ;

      (* move the index i one position right w.r.t. the deque size sz *)
	define inline @move-right (i : int, sz : int) : int =
	    if I32Gte (i, I32Sub (sz, 1)) then
		return (0)
	    else
		return (I32Add (i, 1))
	  ;


      define inline @is-empty (deq : deque) : bool =
	  if I32Eq (LOAD_DEQUE_NEW(deq), LOAD_DEQUE_OLD(deq)) then
	      return (true)
	  else
	      return (false)
	;

      define inline @is-full (deq : deque) : bool =
	  let size : int = @size (deq)
        (* leave one space open *)
	  if I32Gte (size, I32Sub (LOAD_DEQUE_MAX_SIZE(deq), 1)) then
	      return (true)
	  else
	      return (false)
	;

      define inline @new-primary-deque-in-atomic (self : vproc, workerId : UID.uid, size : int) : deque =
	  let deq : deque = ccall M_PrimaryDequeAlloc (self, workerId, size)
          return (deq)
	;

      define inline @new-secondary-deque-in-atomic (self : vproc, workerId : UID.uid, size : int) : deque =
	  let deq : deque = ccall M_SecondaryDequeAlloc (self, workerId, size)
          return (deq)
	;

      define inline @new-resume-deque-in-atomic (self : vproc, workerId : UID.uid, size : int) : deque =
	  let deq : deque = ccall M_ResumeDequeAlloc (self, workerId, size)
          return (deq)
	;

       define inline @is-full-in-atomic (self : vproc, deq : deque) : bool =
           do assert(I32Gt (LOAD_DEQUE_NCLAIMED(deq), 0))
	   @is-full (deq)
	 ;

       define inline @is-empty-in-atomic (self : vproc, deq : deque) : bool =
           do assert(I32Gt (LOAD_DEQUE_NCLAIMED(deq), 0))
	   @is-empty (deq)
	 ;
      
      define inline @is-claimed-in-atomic (self : vproc, deq : deque) : bool =
          if I32Eq (LOAD_DEQUE_NCLAIMED(deq), 0) then
	      return (false)
	  else
	      return (true)
        ;
       
    (* precondition: the deque is not full *)
      define inline @push-new-end-in-atomic (self : vproc, deq : deque, elt : any) : () =
	  do assert(NotEqual (deq, enum(0):any))
	  do assert(I32Gt (LOAD_DEQUE_NCLAIMED(deq), 0))
	  do @check-deque (deq)
	  do assert(NotEqual(elt, DEQUE_NIL_ELT))
	  let isFull : bool = @is-full (deq)
(*           do assert(BNot (isFull))*)
	  let new : int = LOAD_DEQUE_NEW(deq)
	  let newR : int = @move-right (LOAD_DEQUE_NEW(deq), LOAD_DEQUE_MAX_SIZE(deq))
	  do STORE_DEQUE_NEW(deq, newR)
	  do @update (deq, new, elt)
	  do @check-deque (deq)
	  return ()
	;

      define inline @pop-new-end-in-atomic (self : vproc, deq : deque) : Option.option =
	  do assert(NotEqual (deq, enum(0):any))
	  do assert(I32Gt (LOAD_DEQUE_NCLAIMED(deq), 0))
	  do @check-deque (deq)
	  let isEmpty : bool = @is-empty (deq)
	  case isEmpty
	   of true =>
	      return (Option.NONE)
	    | false =>
	      let newL : int = @move-left (LOAD_DEQUE_NEW(deq), LOAD_DEQUE_MAX_SIZE(deq))
	      let elt : any = @sub (deq, newL)
	      do @update (deq, newL, DEQUE_NIL_ELT)
	      do STORE_DEQUE_NEW(deq, newL)
	      do @check-deque (deq)
	      do assert(NotEqual(elt, DEQUE_NIL_ELT))
	      return (Option.SOME (elt))
	  end
	;

      define inline @pop-old-end-in-atomic (self : vproc, deq : deque) : Option.option =
	  do assert(I32Gt (LOAD_DEQUE_NCLAIMED(deq), 0))
	  do @check-deque (deq)
	  let isEmpty : bool = @is-empty (deq)
	  case isEmpty
	   of true =>
	      return (Option.NONE)
	    | false =>
	      let old : int = LOAD_DEQUE_OLD(deq)
	      let elt : any = @sub (deq, old)
	      do @update (deq, old, DEQUE_NIL_ELT)
	      let oldR : int = @move-right (LOAD_DEQUE_OLD(deq), LOAD_DEQUE_MAX_SIZE(deq))
	      do STORE_DEQUE_OLD(deq, oldR)
	      do @check-deque (deq)
	      return (Option.SOME(elt))
	  end
	;

    (* returns the primary deque associated with the given vproc and the work group id. all the deques in this list are 
     * automatically claimed for the caller. *)
      define @primary-deque-in-atomic (self : vproc, workGroupId : UID.uid) : Option.option =
          let deq : deque = ccall M_PrimaryDeque (self, workGroupId)
          let bDeq : [deque] = alloc (deq)
          if Equal (deq, M_NIL) then
	      return (Option.NONE)
	  else
              return (Option.SOME (bDeq))
        ;

    (* returns the secondary deque associated with the given vproc and the work group id. all the deques in this list are 
     * automatically claimed for the caller. *)
      define @secondary-deque-in-atomic (self : vproc, workGroupId : UID.uid) : Option.option =
          let deq : deque = ccall M_SecondaryDeque (self, workGroupId)
          let bDeq : [deque] = alloc (deq)
          if Equal (deq, M_NIL) then
	      return (Option.NONE)
	  else
              return (Option.SOME (bDeq))
        ;

    (* returns all nonempty resume deques associated with the given vproc and the work group id. all the deques in this list are 
     * automatically claimed for the caller. *)
      define @resume-deques-in-atomic (self : vproc, workGroupId : UID.uid) : (* [deque] *) List.list =
          let deques : List.list = ccall M_ResumeDeques (self, workGroupId)
          return (deques)
        ;

      define inline @release-in-atomic (self : vproc, deq : deque) : () =
          do assert(I32Gt (LOAD_DEQUE_NCLAIMED(deq), 0))
          do STORE_DEQUE_NCLAIMED(deq, I32Sub (LOAD_DEQUE_NCLAIMED(deq), 1))
          return ()
        ;

      define @release-deques-in-atomic (self : vproc, deques : List.list) : () =
          fun release (deq : [deque] / _ : exh) : () = @release-in-atomic (self, #0(deq))
          cont exh (_ : exn) = return ()
          PrimList.@app (release, deques / exh)
	;

    (* double the size of the deque *)
      define @double-size-in-atomic (self : vproc, workGroupId : UID.uid, deq : deque) : deque =
          do assert(I32Gt (LOAD_DEQUE_NCLAIMED(deq), 0))
	  let size : int = @size (deq)
	  let newDeque : deque = @new-primary-deque-in-atomic (self, workGroupId, I32Mul (LOAD_DEQUE_MAX_SIZE(deq), 2))
        (* maintain the original order of the deque by popping from the old end of the original deque
	 * and pushing on the new end of the fresh deque
	 *)
	  fun copy () : () =
	      let elt : Option.option = @pop-old-end-in-atomic (self, deq)
              case elt
	       of Option.NONE =>
		  return ()
		| Option.SOME (elt : any) =>
		  do @push-new-end-in-atomic (self, newDeque, elt)
                  apply copy ()
              end
          do apply copy ()
          do @release-in-atomic (self, deq)
	  return (newDeque)
	;

    (* the list of returned threads is ordered from oldest to youngest *)
      define @to-list-in-atomic (self : vproc, deq : deque) : (* ImplicitThread.thread *) List.list =
	  fun lp () : List.list =
	      let thd : Option.option = @pop-old-end-in-atomic (self, deq)
	      case thd
	       of Option.NONE =>
		  return (List.nil)
		| Option.SOME (thd : ImplicitThread.thread) =>
		  let rest : List.list = apply lp ()
		  return (CONS (thd, rest))
	      end
	  apply lp ()
	;

    (* the list of threads is inserted at the new end of the deque *)
      define @add-list-in-atomic (self : vproc, deq : deque, thds : List.list) : () =
          fun add (thd : ImplicitThread.thread / _ : exh) : () = @push-new-end-in-atomic (self, deq, thd)
          cont exh (_ : exn) = return ()
          PrimList.@app (add, thds / exh)
	;

    )

  end
