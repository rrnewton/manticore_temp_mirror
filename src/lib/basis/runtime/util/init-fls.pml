(* init-fls.pml
 *
 * COPYRIGHT (c) 2008 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 *
 * Initialize fiber-local storage for the program.
 *)

structure InitFLS =
  struct

    structure PT = PrimTypes
    structure TC = ThreadCapabilities
    structure FLS = FiberLocalStorage

    _primcode(

      define @defaults (fls : FLS.fls / exh : PT.exh) : FLS.fls =
      (* one touch futures *)
        fun init (x : PT.unit / exh : PT.exh) : any =
	    let readyQ : LockedQueue.queue = Future1.@init-gang-sched( / exh)
            return((any)readyQ)
	let c0 : TC.capability = TC.@init(tag(future1GangSched), init / exh)
        let fls : FLS.fls = TC.@add(fls, c0 / exh)
      (* cancelation for one touch futures *)
        let c0 : ![Option.option] = alloc(Option.NONE)
        let c0 : ![Option.option] = promote(c0)
        let fls : FLS.fls = FLS.@add(fls, tag(future1Cancelation), c0 / exh)
      (* cilk5 work stealing *)
        fun init (x : PT.unit / exh : PT.exh) : any =
	    let deques : Array64.array = Cilk5WorkStealing.@init( / exh)
            return((any)deques)
	let c0 : TC.capability = TC.@init(tag(cilk5WorkStealing), init / exh)
        let fls : FLS.fls = TC.@add(fls, c0 / exh)

	return(fls)
      ;

    (* initial fiber-local storage for the program *)
      define @init (x : PT.unit / exh : PT.exh) : PT.unit = 
	let fls : FLS.fls = FLS.@new (UNIT / exh)
	let fls : FLS.fls = @defaults(fls / exh)
	FLS.@set(fls / exh)
      ;

    )

    val init : unit -> unit = _prim(@init)
    val _ = init()

  end