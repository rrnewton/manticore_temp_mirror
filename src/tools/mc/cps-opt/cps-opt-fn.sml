(* cps-opt-fn.sml
 *
 * COPYRIGHT (c) 2007 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 *)

functor CPSOptFn (Spec : TARGET_SPEC) : sig

    val optimize : CPS.module -> CPS.module

  end = struct

  (* a wrapper for BOM optimization passes.  The wrapper includes an invariant check. *)
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
    val census = analyze {passName = "census", pass = Census.census}
    val cfa = analyze {passName = "cfa", pass = CFACPS.analyze}

  (* wrap transformation passes with keep controls *)
    val contract = transform {passName = "contract", pass = Contract.transform}
    val eta = transform {passName = "eta", pass = EtaExpand.transform}
    val arity = transform {passName = "flatten", pass = ArityRaising.transform}

    fun optimize module = let
	  val _ = census module
	  val module = eta module
	  val module = contract module
          val _ = cfa module
	  val module = arity module
	  val _ = census module
	  val module = contract module
          val _ = CFACPS.clearInfo module
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
