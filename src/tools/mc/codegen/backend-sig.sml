(* backend-sig.sml
 * 
 * COPYRIGHT (c) 2007 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 *
 * Glue code between the code generator and MLRISC.
 *)

signature BACK_END =
  sig

    structure ManticorePseudoOps : MANTICORE_PSEUDO_OPS
	where P.T.Region = ManticoreRegion
    structure MLTreeComp : MLTREECOMP
	where TS.T = ManticorePseudoOps.P.T
	where TS.S.P = ManticorePseudoOps.PseudoOps
    structure MLTreeUtils : MLTREE_UTILS
	where T = MLTreeComp.TS.T
    structure CFGGen : CONTROL_FLOWGRAPH_GEN
	where CFG = MLTreeComp.CFG
	where I = MLTreeComp.I
	where S = MLTreeComp.TS.S

    structure SpillLoc : SPILL_LOC
    structure Spec : TARGET_SPEC
    structure Regs : MANTICORE_REGS
    structure MTy : MLRISC_TYPES
	where T = MLTreeComp.TS.T
    structure LabelCode : LABEL_CODE
	where MTy = MTy
    structure Alloc : ALLOC
	where MTy = MTy
    structure AtomicOps : ATOMIC_OPS
        where MTy = MTy
    structure Types : ARCH_TYPES
    structure Copy : COPY
	where MTy = MTy
    structure VarDef : VAR_DEF		     
	where MTy = MTy
    structure Transfer : TRANSFER
	where MTy = MTy
	where VarDef = VarDef
        where SpillLoc = SpillLoc
    structure VProcOps : VPROC_OPS
	where VarDef = VarDef
	where MTy = MTy

  (* literals that MLRISC introduces during instruction selection *)
    val literals : (Label.label * ManticorePseudoOps.PseudoOps.pseudo_op) list ref

    (* take a control-flow graph, do RA, optimization, etc. and then
     * emit it to the assembly file.
     *)
    val compileCFG : CFGGen.CFG.cfg -> unit
						     
  end (* BACK_END *)
