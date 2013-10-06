(* cps-opt-fn.sml
 *
 * COPYRIGHT (c) 2007 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 *)

functor CPSOptFn (Spec : TARGET_SPEC) : sig

    val optimize : CPS.module -> CPS.module

  end = struct

    structure ArityRaising = ArityRaisingFn (Spec)
                               
  (* a wrapper for CPS optimization passes.  The wrapper includes an invariant check. *)
    fun transform {passName, pass} = let
	  val xform = BasicControl.mkKeepPassSimple {
		  output = PrintCPS.output,
		  ext = "cps",
		  passName = passName,
		  pass = pass,
		  registry = CPSOptControls.registry
		}
	  fun xform' module = let
		val module = xform module
		val _ = CheckCPS.check (passName, module)
		in
		  module
		end
	  in
	    xform'
	  end

  (* a wrapper for CPS analysis passes *)
    fun analyze {passName, pass} = BasicControl.mkTracePassSimple {
            passName = passName,
            pass = pass
          }

  (* wrap analysis passes *)
    val census = analyze {passName = "census", pass = CPSCensus.census}
    val cfa = analyze {passName = "cfa", pass = CFACPS.analyze}

  (* wrap transformation passes with keep controls *)
    val contract = transform {passName = "contract", pass = Contract.transform}
    val elim = transform {passName = "elim", pass = ElimUncalled.transform}
    val eta = transform {passName = "eta-expand", pass = EtaExpand.transform}
    val arity = transform {passName = "arity-raising", pass = ArityRaising.transform}
    val copy = transform {passName = "copy-propagation", pass = CopyPropagation.transform}
    val inline = transform {passName = "inline", pass = Inline.transform}
    val cse = transform {passName = "cse", pass = CommonSubexpressionElimination.transform}
    val branch = transform {passName = "branch-elim", pass = BranchElim.transform}

    val reorder = transform {passName = "reorder-funs", pass = FunctionHoisting.transform}

    fun optimize module = let
	  val _ = census module
	  val _ = CheckCPS.check ("convert", module)
	  val module = contract module
          val _ = cfa module
          val module = elim module
	  val module = branch module
	  val _ = CFACPS.clearInfo module
	  val _ = cfa module
          val module = copy module 
	  val module = eta module
          val _ = CFACPS.clearInfo module 
          val _ = cfa module
	  val module = arity module
	  val module = contract module
	  val _ = CFACPS.clearInfo module
          val _ = cfa module
          val module = reorder module
	  val _ = CFACPS.clearInfo module
	  val _ = cfa module
	  val module = inline module 
          val _ = CFACPS.clearInfo module
          val module = cse module
          val module = contract module
	  in
	    module
	  end

    val optimize = BasicControl.mkKeepPassSimple {
	    output = PrintCPS.output,
            ext = "cps",
            passName = "optimize",
            pass = optimize,
            registry = CPSOptControls.registry
	  }

  end
