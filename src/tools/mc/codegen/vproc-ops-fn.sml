(* vproc-ops-fn.sml
 *
 * COPYRIGHT (c) 2007 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 *
 * Generate code for accessing and modifying fields in the vproc structure.
 *)

signature VPROC_OPS =
  sig

    structure MTy : MLRISC_TYPES
    structure VarDef : VAR_DEF

  (* this expression is a pointer to the host vproc structure. *)
    val genHostVP  : MTy.mlrisc_tree
    val genHostVP' : MTy.T.rexp

  (* load a value from a given offset off the vproc structure. *)
    val genVPLoad  : VarDef.var_def_tbl -> (MTy.T.ty * CFG.offset * CFG.var) -> MTy.mlrisc_tree
    val genVPLoad' : (MTy.T.ty * CFG.offset * MTy.T.rexp) -> MTy.T.rexp

  (* store a value at an offset from the vproc structure. *)
    val genVPStore  : VarDef.var_def_tbl -> (MTy.T.ty * CFG.offset * CFG.var * CFG.var) -> MTy.T.stm
    val genVPStore' : (MTy.T.ty * CFG.offset * MTy.T.rexp * MTy.T.rexp) -> MTy.T.stm

  (* compute an offset off the vproc structure. *)
    val genVPAddrOf  : VarDef.var_def_tbl -> (CFG.offset * CFG.var) -> MTy.mlrisc_tree
    val genVPAddrOf' : (CFG.offset * MTy.T.rexp) -> MTy.T.rexp

  end (* VPROC_OPS *)

functor VProcOpsFn (
    structure MTy : MLRISC_TYPES
    structure VarDef : VAR_DEF where MTy = MTy
    structure Regs : MANTICORE_REGS
    structure Spec : TARGET_SPEC
    structure Types : ARCH_TYPES
    structure MLTreeComp : MLTREECOMP 
  ) : VPROC_OPS = struct
  
    structure MTy = MTy
    structure VarDef = VarDef
    structure W = Word64
    structure Cells = MLTreeComp.I.C
    structure T = MTy.T
  
    val ty = MTy.wordTy
    val memory = ManticoreRegion.memory

    val genHostVP' = T.ANDB(ty, T.REG(ty, Regs.apReg), T.LI Spec.ABI.vpMask)

    val genHostVP = MTy.EXP(ty, genHostVP')
  
    fun genVPAddrOf' (offset, vp) = T.ADD(ty, vp, T.LI offset)

    fun genVPAddrOf varDefTbl (offset, vp) =
	  MTy.EXP (ty, genVPAddrOf' (offset, VarDef.defOf varDefTbl vp))

    fun genVPLoad' (ty, offset, vp) = T.LOAD(ty, genVPAddrOf' (offset, vp), memory)

    fun genVPLoad varDefTbl (ty, offset, vproc) =
	  MTy.EXP (ty, genVPLoad' (ty, offset, VarDef.defOf varDefTbl vproc))
  
    fun genVPStore' (ty, offset, vp, v) = T.STORE (ty, genVPAddrOf' (offset, vp), v, memory)
  
    fun genVPStore varDefTbl (ty, offset, vproc, v) =
	  genVPStore' (ty, offset, VarDef.defOf varDefTbl vproc, 
		    VarDef.defOf varDefTbl v)
  
  end (* VProcOpsFn *)
