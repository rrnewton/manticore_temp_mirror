(* bom-opt-fn.sml
 *
 * COPYRIGHT (c) 2007 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 *)

functor BOMOptFn (Spec : TARGET_SPEC) : sig

    val optimize : BOM.module -> BOM.module

  end = struct

    fun checkBOM (passName, module, alwaysCheck) = 
        if alwaysCheck orelse !BOMOptControls.checkAll
        then CheckBOM.check (passName, module)
        else true

  (* a wrapper for BOM optimization passes.  The wrapper includes an invariant check. *)
    fun transform {passName, pass} = let
	  val xform = BasicControl.mkKeepPassSimple {
		  output = PrintBOM.output,
		  ext = "bom",
		  passName = passName,
		  pass = pass,
		  registry = BOMOptControls.registry
		}
	  fun xform' module = let
		val module = xform module
		val _ = checkBOM (passName, module, false)
		in
		  module
		end
	  in
	    xform'
	  end

    fun moduleOptOutput (out, NONE) = ()
      | moduleOptOutput (out, SOME p) = PrintBOM.output (out, p)

    fun mkModuleOptPass (passName, pass) = BasicControl.mkKeepPass {
	    preOutput = PrintBOM.output,
	    preExt = "bom",
	    postOutput = moduleOptOutput,
	    postExt = "bom",
	    passName = passName,
	    pass = pass,
	    registry = BOMOptControls.registry
	  }

    fun analyze {passName, pass} = BasicControl.mkTracePassSimple {
            passName = passName,
            pass = pass
          }

    val expand = mkModuleOptPass ("expand", ExpandHLOps.expand)

    val contract = transform {
	    passName = "contract",
	    pass = Contract.contract {removeExterns=true}
	  }
    val expandAllContract = transform {
	    passName = "expand-all-contract",
	    pass = Contract.contract {removeExterns=false}
	  }
    val rewriteAllContract = transform {
	    passName = "rewrite-all-contract",
	    pass = Contract.contract {removeExterns=false}
	  }

    val rewrite = mkModuleOptPass ("rewrite", RewriteHLOps.rewrite)

    fun expandAll module = (case expand module
	   of SOME module => let
		val _ = checkBOM ("expand-all:expand", module, false)
	      (* NOTE: we don't remove externs here because references may
	       * be hiding inside unexpanded HLOps.
	       *)
		val module = expandAllContract module
		val _ = checkBOM ("expand-all:contract", module, false)
		in
		  expandAll module
		end
	    | NONE => ExpandHLOps.finish module
	  (* end case *))

(* FIXME: rewriting and expansion should be interleaved!!! *)
    fun rewriteAll module = (case rewrite module
	   of SOME module => let
(*		val _ = checkBOM ("rewrite-all:rewrite", module, false)*)
	      (* NOTE: we don't remove externs here because references may be hiding inside
	       * unexpanded HLOps.
	       *)
(*		val module = rewriteAllContract module
		val _ = checkBOM ("rewrite-all:contract", module, false)
*)
		in
		  rewriteAll module
		end
	    | NONE => module
	  (* end case *))

  (* the expansive inlining pass *)
    fun inline specializeRecFuns = let
	  val xform = BasicControl.mkKeepPassSimple {
		  output = PrintBOM.output,
		  ext = "bom",
		  passName = "inline",
		  pass = Inline.transform {specializeRecFuns=specializeRecFuns},
		  registry = BOMOptControls.registry
		}
	  fun xform' module = let
		val module = xform module
		val _ = checkBOM ("inline", module, false)
		in
		  module
		end
	  in
	    xform'
	  end

    val groupFuns = transform {passName = "group-funs", pass = GroupFuns.transform}
    val deadFuns = transform {passName = "dead-funs", pass = DeadFuns.transform}
    val uncurry = transform {passName = "uncurry", pass = Uncurry.transform}
    val caseSimplify = transform {passName = "case-simplify", pass = CaseSimplify.transform}
    val removeAtomics = transform {passName = "remove-atomics", pass = RemoveAtomics.transform}
    val rewriteAll = transform {passName = "rewrite-all", pass = rewriteAll}
    val expandAll = transform {passName = "expand-all", pass = expandAll}
    val cfa = analyze {passName = "cfa", pass = CFABOM.analyze}
    val flatten = transform {passName = "flatten", pass = Flatten.transform}

    fun optimize module = let
	  val _ = Census.census module
          val _ = checkBOM ("translate", module, true)
	  val module = contract module
	  val module = inline false module  
	  val module = contract module
          val _ = cfa module
          val module = removeAtomics module
          val module = rewriteAll module
	  val module = expandAll module
	(* FIXME: rerun the census to get the counts for HLOp code right. *)
	  val _ = Census.census module
	(* NOTE: we cannot run groupFuns until after HLOp expansion, since it doesn't know the
	 * recursive dependencies of the HLOps.
	 *)
	  val module = groupFuns module
	  val module = deadFuns module
	  val module = inline true module
	  val module = contract module  
	  val module = uncurry module
	  val module = contract module
	  val module = caseSimplify module
	  val module = contract module
          val module = flatten module
          val module = contract module
          val _ = checkBOM ("finalPostContract", module, true)
	  in
	    module
	  end

    val optimize = BasicControl.mkKeepPassSimple {
	    output = PrintBOM.output,
	    ext = "bom",
	    passName = "optimize",
	    pass = optimize,
	    registry = BOMOptControls.registry
	  }

  end
