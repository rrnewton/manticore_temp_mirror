(* prim-gen-fn.sml
 *
 * COPYRIGHT (c) 2007 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 *)

signature PRIM_GEN =
  sig

    structure BE : BACK_END

    type ctx = {varDefTbl : BE.VarDef.var_def_tbl}

    val genPrim0 : ctx -> CFG.prim -> BE.MTy.T.stm list
    val genPrim : ctx -> (CFG.var * CFG.prim) -> BE.MTy.T.stm list

  end (* PRIM_GEN *)

functor PrimGenFn (structure BE : BACK_END) : PRIM_GEN =
  struct

    structure BE = BE
    structure MTy = BE.MTy
    structure T = MTy.T
    structure M = CFG
    structure Var = M.Var
    structure Ty = CFGTy
    structure P = Prim
    structure Cells = BE.MLTreeComp.I.C

    type ctx = {varDefTbl : BE.VarDef.var_def_tbl}

    val anyTy = 64	(* MLRISC type of "any" *)
    val i32Ty = 32
    val i64Ty = 64
    val f32Ty = 32
    val f64Ty = 64
    val boolTy = 64

    fun wordLit i = T.LI (T.I.fromInt (i64Ty, i))

    fun arrayOffset {base, i, wordSzB} = T.ADD (MTy.wordTy, base, T.MULS(MTy.wordTy, wordLit wordSzB, i))

    fun genPrim0 {varDefTbl} p = (case p
	(* memory-system operations *)
          of P.Pause => BE.AtomicOps.genPause()
	   | P.FenceRead => let
	       val stms = BE.AtomicOps.genFenceRead()
	       in
		 BE.VarDef.flushLoads varDefTbl
		 @ stms
	       end
	   | P.FenceWrite => let
	       val stms = BE.AtomicOps.genFenceWrite()
	       in
		 BE.VarDef.flushLoads varDefTbl
		 @ stms
	       end
	   | P.FenceRW	 => let
	       val stms = BE.AtomicOps.genFenceRW()
	       in
		 BE.VarDef.flushLoads varDefTbl
		 @ stms
	       end
	   | _ => raise Fail(concat[
		  "genPrim0(", PrimUtil.fmt CFG.Var.toString p, ")"
		])
	  (* end case *))

    fun genPrim {varDefTbl} = let
	  val getDefOf = BE.VarDef.getDefOf varDefTbl
	  val setDefOf = BE.VarDef.setDefOf varDefTbl
	  val defOf = BE.VarDef.defOf varDefTbl
	  val fdefOf = BE.VarDef.fdefOf varDefTbl
	  val cdefOf = BE.VarDef.cdefOf varDefTbl
	  val gprBind = BE.VarDef.gprBind varDefTbl
	  val cbind = BE.VarDef.cbind varDefTbl
	  val fbind = BE.VarDef.fbind varDefTbl

	  fun gen (v, p) = let
		fun genCmp (ty, c, (v1, v2)) = 
		      cbind (v, T.CMP (ty, c, defOf v1, defOf v2))
		fun genFCmp (ty, c, (v1, v2)) = 
		      cbind (v, T.FCMP (ty, c, fdefOf v1, fdefOf v2))
		fun genArith1 (ty, oper, v') = 
		      gprBind (ty, v, oper (ty, defOf v'))
		fun genArith2 (ty, oper, (v1, v2)) = 
		      gprBind (ty, v, oper (ty, defOf v1, defOf v2))
		fun genFArith1 (fty, oper, v') = 
		      fbind (fty, v, oper (fty, fdefOf v'))
		fun genFArith2 (fty, oper, (v1, v2)) = 
		      fbind (fty, v, oper (fty, fdefOf v1, fdefOf v2))
		fun divs (ty, a, b) = T.DIVS(T.DIV_TO_ZERO, ty, a, b)
		fun rems (ty, a, b) = T.REMS(T.DIV_TO_ZERO, ty, a, b)
		fun genLoad (sz, bind, ld) (base, i) = let
		      val addr = arrayOffset {base=defOf base, i=defOf i, wordSzB=4}
		      in
			bind (sz, v, ld(sz, addr, ManticoreRegion.memory))
		      end
		in
		  case p
		   of P.isBoxed p => 
			cbind (v, T.CMP(anyTy, T.EQ, T.ANDB(anyTy, defOf p, wordLit 1), wordLit 0))
		    | P.isUnboxed p => 
			cbind (v, T.CMP(anyTy, T.NE, T.ANDB(anyTy, defOf p, wordLit 1), wordLit 0))
		    | P.Equal a => genCmp (anyTy, T.EQ, a)
		    | P.NotEqual a => genCmp (anyTy, T.NE, a)
		    | P.BNot a => let
			val dst = Cells.newReg()
			in
			  T.MV(anyTy, dst, T.COND(anyTy, T.CMP(anyTy, T.Basis.EQ, T.LI BE.Spec.trueRep, defOf(a)),
			    T.LI BE.Spec.falseRep, T.LI BE.Spec.trueRep)) ::
			  gprBind(anyTy, v, T.REG(anyTy, dst))
			end
		    | P.BEq a => genCmp (anyTy, T.EQ, a)
		    | P.BNEq a => genCmp (anyTy, T.NE, a)
		   (* 32-bit integer primitives *)				  
		    | P.I32Add a => genArith2 (i32Ty, T.ADD, a)
		    | P.I32Sub a => genArith2 (i32Ty, T.SUB, a)
		    | P.I32Mul a => genArith2 (i32Ty, T.MULS, a)
		    | P.I32Div a => genArith2 (i32Ty, divs, a)
		    | P.I32Mod a => genArith2 (i32Ty, rems, a)
		    | P.I32LSh a => genArith2 (i32Ty, T.SLL, a)
		    | P.I32Neg a => genArith1 (i32Ty, T.NEG, a)
		    | P.I32Eq a => genCmp (i32Ty, T.EQ, a)
		    | P.I32NEq a => genCmp (i32Ty, T.NE, a)
		    | P.I32Lt a => genCmp (i32Ty, T.LT, a)
		    | P.I32Lte a => genCmp (i32Ty, T.LE, a)
		    | P.I32Gt a => genCmp (i32Ty, T.GT, a)
		    | P.I32Gte a => genCmp (i32Ty, T.GE, a)
		   (* 64-bit integer primitives *)
		    | P.I64Add a => genArith2 (i64Ty, T.ADD, a)
		    | P.I64Sub a => genArith2 (i64Ty, T.SUB, a)
		    | P.I64Mul a => genArith2 (i64Ty, T.MULS, a)
		    | P.I64Div a => genArith2 (i64Ty, divs, a)
		    | P.I64Mod a => genArith2 (i64Ty, rems, a)
		    | P.I64Neg a => genArith1 (i64Ty, T.NEG, a)
		    | P.I64Eq a => genCmp (i64Ty, T.EQ, a)
		    | P.I64NEq a => genCmp (i64Ty, T.NE, a)
		    | P.I64Lt a => genCmp (i64Ty, T.LT, a)
		    | P.I64Lte a => genCmp (i64Ty, T.LE, a)
		    | P.I64Gt a => genCmp (i64Ty, T.GT, a)
		    | P.I64Gte a => genCmp (i64Ty, T.GE, a)
		  (* 32-bit floating-point *)
		    | P.F32Add a => genFArith2 (f32Ty, T.FADD, a)
		    | P.F32Sub a => genFArith2 (f32Ty, T.FSUB, a)
		    | P.F32Mul a => genFArith2 (f32Ty, T.FMUL, a)
		    | P.F32Div a => genFArith2 (f32Ty, T.FDIV, a)
		    | P.F32Neg a => genFArith1 (f32Ty, T.FNEG, a)
		    | P.F32Sqrt a => genFArith1 (f32Ty, T.FSQRT, a)
		    | P.F32Abs a => genFArith1 (f32Ty, T.FABS, a)
		    | P.F32Eq a => genFCmp (f32Ty, T.==, a)
		    | P.F32NEq a => genFCmp (f32Ty, T.<>, a)
		    | P.F32Lt a => genFCmp (f32Ty, T.<, a)
		    | P.F32Lte a => genFCmp (f32Ty, T.<=, a)
		    | P.F32Gt a => genFCmp (f32Ty, T.>, a)
		    | P.F32Gte a => genFCmp (f32Ty, T.>=, a)
		  (* 64-bit floating-point *)
		    | P.F64Add a => genFArith2 (f64Ty, T.FADD, a)
		    | P.F64Sub a => genFArith2 (f64Ty, T.FSUB, a)
		    | P.F64Mul a => genFArith2 (f64Ty, T.FMUL, a)
		    | P.F64Div a => genFArith2 (f64Ty, T.FDIV, a)
		    | P.F64Neg a => genFArith1 (f64Ty, T.FNEG, a)
		    | P.F64Sqrt a => genFArith1 (f64Ty, T.FSQRT, a)
		    | P.F64Abs a => genFArith1 (f64Ty, T.FABS, a)
		    | P.F64Eq a => genFCmp (f64Ty, T.==, a)
		    | P.F64NEq a => genFCmp (f64Ty, T.<>, a)
		    | P.F64Lt a => genFCmp (f64Ty, T.<, a)
		    | P.F64Lte a => genFCmp (f64Ty, T.<=, a)
		    | P.F64Gt a => genFCmp (f64Ty, T.>, a)
		    | P.F64Gte a => genFCmp (f64Ty, T.>=, a)
		  (* conversions *)
		    | P.I32ToI64X x => gprBind (i64Ty, v, T.SX(i64Ty, i32Ty, defOf x))
		    | P.I32ToI64 x => gprBind (i64Ty, v, T.ZX(i64Ty, i32Ty, defOf x))
		    | P.I32ToF32 x => fbind (f32Ty, v, T.CVTI2F(f32Ty, i32Ty, defOf x))
		    | P.I32ToF64 x => fbind (f64Ty, v, T.CVTI2F(f64Ty, i32Ty, defOf x))
		    | P.I64ToF32 x => fbind (f32Ty, v, T.CVTI2F(f32Ty, i64Ty, defOf x))
		    | P.I64ToF64 x => fbind (f64Ty, v, T.CVTI2F(f64Ty, i64Ty, defOf x))
		    | P.F64ToI32 x => gprBind (i32Ty, v, T.CVTF2I(i32Ty, T.Basis.TO_NEAREST, f64Ty, fdefOf x))
		  (* array load operations *)
		    | P.ArrayLoadI32(base, i) => genLoad (i32Ty, gprBind, T.LOAD) (base, i)
		    | P.ArrayLoadI64(base, i) => genLoad (i64Ty, gprBind, T.LOAD) (base, i)
		    | P.ArrayLoadF32(base, i) => genLoad (f32Ty, fbind, T.FLOAD) (base, i)
		    | P.ArrayLoadF64(base, i) => genLoad (f64Ty, fbind, T.FLOAD) (base, i)
		    | P.ArrayLoad(base, i) => genLoad (anyTy, gprBind, T.LOAD) (base, i)
		  (* array store operations *)
		    | P.ArrayStoreI32 (base, i, x) => let
			val addr = arrayOffset {base=defOf base, i=defOf i, wordSzB=4}
			in
			  BE.VarDef.flushLoads varDefTbl @
			  [T.STORE(i32Ty, addr, defOf x, ManticoreRegion.memory)] @
			  gprBind(i32Ty, v, T.LI BE.Spec.trueRep)
		       end
		    | P.ArrayStoreI64(base, i, x) => let
			val addr = arrayOffset {base=defOf base, i=defOf i, wordSzB=8}
			in
			  BE.VarDef.flushLoads varDefTbl @
			  [T.STORE(i64Ty, addr, defOf x, ManticoreRegion.memory)] @
			  gprBind(i32Ty, v, T.LI BE.Spec.trueRep)
			end
		    | P.ArrayStoreF32 (base, i, x) => let
			val addr = arrayOffset {base=defOf base, i=defOf i, wordSzB=4}
			in
			  BE.VarDef.flushLoads varDefTbl @
			  [T.FSTORE(f32Ty, addr, fdefOf x, ManticoreRegion.memory)] @
			  gprBind(i32Ty, v, T.LI BE.Spec.trueRep)
			end
		    | P.ArrayStoreF64 (base, i, x) => let
			val addr = arrayOffset {base=defOf base, i=defOf i, wordSzB=8}
			in
			  BE.VarDef.flushLoads varDefTbl @
			  [T.FSTORE(f64Ty, addr, fdefOf x, ManticoreRegion.memory)] @
			  gprBind(i32Ty, v, T.LI BE.Spec.trueRep)
		       end
		    | P.ArrayStore(base, i, x) => let
			val addr = arrayOffset {base=defOf base, i=defOf i, wordSzB=8}
			in
			  BE.VarDef.flushLoads varDefTbl @
			  [T.STORE(anyTy, addr, defOf x, ManticoreRegion.memory)] @
			  gprBind(i32Ty, v, T.LI BE.Spec.trueRep)
			end
		  (* atomic operations *)
		    | P.I32FetchAndAdd(addr, x) => let
			val (r, stms) = BE.AtomicOps.genFetchAndAdd32 {
				 addr=T.LOAD(i32Ty, defOf addr, ()),
				 x=defOf x
			       }
			in
			  BE.VarDef.flushLoads varDefTbl
			  @ stms
			  @ gprBind (i32Ty, v, r)
			end
		    | P.I64FetchAndAdd(addr, x) => let
			val (r, stms) = BE.AtomicOps.genFetchAndAdd64 {
				 addr=T.LOAD(i64Ty, defOf addr, ()),
				 x=defOf x
			       }
			in
			  BE.VarDef.flushLoads varDefTbl
			  @ stms
			  @ gprBind (i64Ty, v, r)
			end
		    | P.CAS(addr, key, new) => let
			val (_, r, stms) = BE.AtomicOps.genCompareAndSwapWord{
				    addr = T.LOAD(anyTy, defOf addr, ()),
				    cmpVal = defOf key, newVal = defOf new
				  }
			in
			  BE.VarDef.flushLoads varDefTbl
			  @ stms
			  @ gprBind (anyTy, v, r)
			end
		    | P.TAS addr => let
			val tmp = Cells.newReg ()
			val (r, stms) = BE.AtomicOps.genTestAndSetWord{
				    addr = T.LOAD(boolTy, defOf addr, ()),
				    newVal = tmp
				  }
			in
			  BE.VarDef.flushLoads varDefTbl
			  @ [T.MV (boolTy, tmp, T.LI BE.Spec.trueRep)]
			  @ stms
			  @ gprBind (boolTy, v, r)
			end
		    | P.BCAS(addr, key, new) => let
			val (cc, _, stms) = BE.AtomicOps.genCompareAndSwapWord{
				    addr = T.LOAD(anyTy, defOf addr, ()),
				    cmpVal = defOf key, newVal = defOf new
				  }
			in
(* FIXME *)raise Fail "codegen for BCAS is broken";
			  BE.VarDef.flushLoads varDefTbl
			  @ stms
			  @ cbind (v, cc)
			end
		    | _ => raise Fail(concat[
			  "genPrim(", CFG.Var.toString v, ", ",
			  PrimUtil.fmt CFG.Var.toString p, ")"
			])
		end (* gen *)
	  in
	    gen
	  end (* genPrim *)


  end (* PrimGenFn *)
