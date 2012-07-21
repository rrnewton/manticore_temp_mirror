(* transfer-sig.sml
 * 
 * COPYRIGHT (c) 2007 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 *
 * Generate CFG control transfers.
 *)

signature TRANSFER = sig

    structure MTy : MLRISC_TYPES
    structure VarDef : VAR_DEF where MTy = MTy
    structure SpillLoc : SPILL_LOC

    val stdFuncRegs : CellsBasis.cell list
    val stdContRegs : CellsBasis.cell list

    type stms = MTy.T.stm list

  (* blocks *)
    val genGoto : VarDef.var_def_tbl -> CFG.jump -> stms

  (* known functions *)
    val genApply : VarDef.var_def_tbl -> {
	    f : CFG.var, clos : CFG.var, args : CFG.var list
	  } -> {stms : stms, liveOut : MTy.T.mlrisc list}

  (* standard functions *)
    val genStdApply : VarDef.var_def_tbl -> {
	    f : CFG.var, clos : CFG.var, args : CFG.var list, ret : CFG.var, exh : CFG.var
	  } -> {stms : stms, liveOut : MTy.T.mlrisc list}

    val genStdThrow : VarDef.var_def_tbl -> {
	    k : CFG.var, clos : CFG.var, args : CFG.var list
	  } -> {stms : stms, liveOut : MTy.T.mlrisc list}

  (* perform a heap check, possibly triggering the GC *)
    val genHeapCheck : 
	VarDef.var_def_tbl -> {hck : CFG.heap_check_kind, checkStms : MTy.T.stm list, 
			       allocCheck : MTy.T.ccexp, nogc : CFG.jump}
	  -> {stms : stms, return : (Label.label * stms * MTy.T.mlrisc list) Option.option}

  (* promote an object to the global heap *)
    val genPromote : VarDef.var_def_tbl -> 
 	{lhs: CFG.var, arg: CFG.var} -> 
		     {stms : stms, result : MTy.mlrisc_tree list}

    val genAllocPolyVec : VarDef.var_def_tbl -> 
 	{lhs: CFG.var, arg: CFG.var} -> 
		     {stms : stms, result : MTy.T.rexp}

    val genAllocIntArray : VarDef.var_def_tbl -> 
 	{lhs: CFG.var, n : CFG.var} -> 
		     {stms : stms, result : MTy.T.rexp}

    val genAllocLongArray : VarDef.var_def_tbl -> 
 	{lhs: CFG.var, n : CFG.var} -> 
		     {stms : stms, result : MTy.T.rexp}

    val genAllocFloatArray : VarDef.var_def_tbl -> 
 	{lhs: CFG.var, n : CFG.var} -> 
		     {stms : stms, result : MTy.T.rexp}

    val genAllocDoubleArray : VarDef.var_def_tbl -> 
 	{lhs: CFG.var, n : CFG.var} -> 
		     {stms : stms, result : MTy.T.rexp}

  (* apply a C function f to args.  the result goes in lhs. *)
    val genCCall : VarDef.var_def_tbl ->
	{lhs: CFG.var list, f : CFG.var, args: CFG.var list} -> 
		   {stms : stms, result : MTy.mlrisc_tree list}

  (* apply a C funcion f to args (f can trigger a garbage collection). *)
    val genAllocCCall : VarDef.var_def_tbl ->
	{lhs : CFG.var list, f : CFG.var, args: CFG.var list, ret : CFG.jump} -> 
		   stms

  (* entry to a labelled function *)
    val genFuncEntry :VarDef.var_def_tbl -> (CFG.label * CFG.convention * CFG.block) -> stms

  (* entry to a labelled function *)
    val genBlockEntry :VarDef.var_def_tbl -> (CFG.label * CFG.block) -> stms

  end (* TRANSFER *)
