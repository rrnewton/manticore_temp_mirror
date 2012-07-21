(* add-alloc-vec-checks-fn.sml
 *
 * COPYRIGHT (c) 2010 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 *
 * Vector allocations may trigger garbage collections.  In this pass, transform the CFG
 * such that all corresponding allocation checks are made explicit.
 *)

functor AddAllocVecChecksFn (Target : TARGET_SPEC) : sig

   val transform : CFG.module -> CFG.module

  end = struct

    datatype ('a, 'b) either
      = LEFT of 'a
      | RIGHT of 'b

    structure VSet = CFG.Var.Set
    structure VMap = CFG.Var.Map

    fun deleteList (vSet, vs) = VSet.difference (vSet, VSet.fromList vs)
    val addList = VSet.addList
    val fromList = VSet.fromList

  (* returns the live variables of an expression / control transfer *)
    fun liveVarsOfExp (e, fvs) =
	  deleteList (addList (fvs, CFGUtil.rhsOfExp e), CFG.lhsOfExp e)
    fun liveVarsOfXfer transfer =
	  deleteList (fromList (CFGUtil.varsOfXfer transfer), CFGUtil.lhsOfXfer transfer)
		 
    fun splitBlock (block : CFG.block) : CFG.block list = let
      fun splitBody ([], vs, _) = LEFT vs
	| splitBody (e :: es, vs, fvs) = (case e
	    of CFG.E_Prim (lhs, Prim.AllocPolyVec (n, xs)) => let
                 val vs' = CFG.E_Prim (lhs, Prim.AllocPolyVec (n, xs)) :: vs
		 in
		   RIGHT ("AllocPolyVec", lhs, n, List.rev es, vs', addList (liveVarsOfExp (e, fvs), [n, xs]), 0w8)
	       end
	     | CFG.E_Prim (lhs, Prim.AllocLongArray n) => let
                 val vs' = CFG.E_Prim (lhs, Prim.AllocLongArray n) :: vs
		 in
		   RIGHT ("AllocLongArray", lhs, n, List.rev es, vs', addList (liveVarsOfExp (e, fvs), [n]), 0w8)
	         end
	     | CFG.E_Prim (lhs, Prim.AllocIntArray n) => let
                 val vs' = CFG.E_Prim (lhs, Prim.AllocIntArray n) :: vs
		 in
		   RIGHT ("AllocIntArray", lhs, n, List.rev es, vs', addList (liveVarsOfExp (e, fvs), [n]), 0w4)
	         end
	     | CFG.E_Prim (lhs, Prim.AllocDoubleArray n) => let
                 val vs' = CFG.E_Prim (lhs, Prim.AllocDoubleArray n) :: vs
		 in
		   RIGHT ("AllocDoubleArray", lhs, n, List.rev es, vs', addList (liveVarsOfExp (e, fvs), [n]), 0w8)
	         end
	     | CFG.E_Prim (lhs, Prim.AllocFloatArray n) => let
                 val vs' = CFG.E_Prim (lhs, Prim.AllocFloatArray n) :: vs
		 in
		   RIGHT ("AllocFloatArray", lhs, n, List.rev es, vs', addList (liveVarsOfExp (e, fvs), [n]), 0w4)
	         end
	     | _ => splitBody (es, e :: vs, liveVarsOfExp (e, fvs))
	   (* end case *))
      fun splitBlockLp (CFG.BLK {lab, args, body, exit}, blocks) =
	(case splitBody (List.rev body, [], liveVarsOfXfer exit)
	  of LEFT vs => CFG.BLK {lab=lab, args=args, body=vs, exit=exit} :: blocks
	   | RIGHT (plab, lhs, n, es, vs, fvs, szb) => let
	       val liveVars = VSet.listItems fvs
	       val freshLiveVars = List.map CFG.Var.copy liveVars
	       val env = List.foldl VMap.insert' VMap.empty (ListPair.zip (liveVars, freshLiveVars))
	       val lab' = CFG.Label.new(plab, CFGTy.T_Block{args = List.map CFG.Var.typeOf freshLiveVars})
	       val block' = CFG.mkBlock (lab, args, es, 
				 CFG.HeapCheckN {hck=CFG.HCK_Local, n=n, szb=szb, nogc=(lab', liveVars)})
	       val block'' = CFG.mkBlock (lab', freshLiveVars, 
				      List.map (CFGUtil.substExp env) vs,
				      CFGUtil.substTransfer env exit)
	     in
	       splitBlockLp (block', block'' :: blocks)
	     end
	(* end case *))
      in
	splitBlockLp (block, [])
      end
	
    fun rewriteFunc (func as CFG.FUNC{lab, entry, start, body}) = let
       val export = (case CFG.Label.kindOf lab
		      of CFG.LK_Func{export, ...} => export
		       | _ => raise Fail "bogus label kind"
		    (* end case *))
       val start'::starts = splitBlock start
       val body' = List.concat (starts :: List.map splitBlock body)
       in
	 CFG.mkFunc (lab, entry, start', body', export)
       end
			       
    fun transform (m as CFG.MODULE{name, externs, code}) = let
       val code = List.map rewriteFunc code
       val module = CFG.mkModule (name, externs, code)
       in
	 Census.census module;
	 module
       end (* transform *)

  end (* AddAllocVecChecksFn *)
