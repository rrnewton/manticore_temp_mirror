(* make-prim-fn.sml
 *
 * COPYRIGHT (c) 2007 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 *
 * Ths functor can be used to establish a mapping from atoms to a particular
 * instance of the Prim.prim datatype.
 *)

signature PRIM_TYPES =
  sig
    type var
    type ty

    val anyTy : ty
    val unitTy : ty
    val boolTy : ty
    val addrTy : ty
    val rawTy : RawTypes.raw_ty -> ty

  end

functor MakePrimFn (Ty : PRIM_TYPES) : sig

    datatype prim_info
      = Prim0 of {
	    con : Ty.var Prim.prim,
	    resTy : Ty.ty
	  }
      | Prim1 of {
	    mk : Ty.var -> Ty.var Prim.prim,
	    argTy : Ty.ty,
	    resTy : Ty.ty
	  }
      | Prim2 of {
	    mk : Ty.var * Ty.var -> Ty.var Prim.prim,
	    argTy : Ty.ty * Ty.ty,
	    resTy : Ty.ty
	  }
      | Prim3 of {
	    mk : Ty.var * Ty.var * Ty.var -> Ty.var Prim.prim,
	    argTy : Ty.ty * Ty.ty * Ty.ty,
	    resTy : Ty.ty
	  }

    val findPrim : Atom.atom -> prim_info option

  end = struct

    structure P = Prim

    datatype prim_info
      = Prim0 of {
	    con : Ty.var Prim.prim,
	    resTy : Ty.ty
	  }
      | Prim1 of {
	    mk : Ty.var -> Ty.var Prim.prim,
	    argTy : Ty.ty,
	    resTy : Ty.ty
	  }
      | Prim2 of {
	    mk : Ty.var * Ty.var -> Ty.var Prim.prim,
	    argTy : Ty.ty * Ty.ty,
	    resTy : Ty.ty
	  }
      | Prim3 of {
	    mk : Ty.var * Ty.var * Ty.var -> Ty.var Prim.prim,
	    argTy : Ty.ty * Ty.ty * Ty.ty,
	    resTy : Ty.ty
	  }

    val aTy = Ty.anyTy
    val uTy = Ty.unitTy
    val bTy = Ty.boolTy
    val adrTy = Ty.addrTy
    val i8  = Ty.rawTy RawTypes.T_Byte
    val i16 = Ty.rawTy RawTypes.T_Short
    val i32 = Ty.rawTy RawTypes.T_Int
    val i64 = Ty.rawTy RawTypes.T_Long
    val f32 = Ty.rawTy RawTypes.T_Float
    val f64 = Ty.rawTy RawTypes.T_Double

  (* table mapping primop names to prim_info *)
    val findPrim = let
	  val tbl = AtomTable.mkTable(128, Fail "prim table")
	  val ins = AtomTable.insert tbl
	  fun mk0 (con, resTy) = Prim0 {con=con, resTy=resTy}
	  fun mk cons (mk, argTy, resTy) = cons {mk = mk, argTy = argTy, resTy = resTy}
	  in
	    List.app (fn (n, info) => ins(Atom.atom n, info)) [
		("isBoxed",	mk Prim1 (P.isBoxed,	aTy,		bTy)),
		("isUnboxed",	mk Prim1 (P.isUnboxed,	aTy,		bTy)),
		("Equal",	mk Prim2 (P.Equal,	(aTy, aTy),	bTy)),
		("NotEqual",	mk Prim2 (P.NotEqual,	(aTy, aTy),	bTy)),
		("BNot",	mk Prim1 (P.BNot,	bTy,		bTy)),
		("BEq",		mk Prim2 (P.BEq,	(bTy, bTy),	bTy)),
		("BNEq",	mk Prim2 (P.BNEq,	(bTy, bTy),	bTy)),
		("I32Add",	mk Prim2 (P.I32Add,	(i32, i32),	i32)),
		("I32Sub",	mk Prim2 (P.I32Sub,	(i32, i32),	i32)),
		("I32Mul",	mk Prim2 (P.I32Mul,	(i32, i32),	i32)),
		("I32Div",	mk Prim2 (P.I32Div,	(i32, i32),	i32)),
		("I32Mod",	mk Prim2 (P.I32Mod,	(i32, i32),	i32)),
		("I32LSh",	mk Prim2 (P.I32LSh,	(i32, i32),	i32)),
(*
		("I32RShA",	mk Prim2 (P.I32RShA,	(i32, i32),	i32)),
		("I32RShL",	mk Prim2 (P.I32RShL,	(i32, i32),	i32)),
*)
		("I32Neg",	mk Prim1 (P.I32Neg,	i32,		i32)),
		("I32Eq",	mk Prim2 (P.I32Eq,	(i32, i32),	bTy)),
		("I32NEq",	mk Prim2 (P.I32NEq,	(i32, i32),	bTy)),
		("I32Lt",	mk Prim2 (P.I32Lt,	(i32, i32),	bTy)),
		("I32Lte",	mk Prim2 (P.I32Lte,	(i32, i32),	bTy)),
		("I32Gt",	mk Prim2 (P.I32Gt,	(i32, i32),	bTy)),
		("I32Gte",	mk Prim2 (P.I32Gte,	(i32, i32),	bTy)),
		("I64Add",	mk Prim2 (P.I64Add,	(i64, i64),	i64)),
		("I64Sub",	mk Prim2 (P.I64Sub,	(i64, i64),	i64)),
		("I64Mul",	mk Prim2 (P.I64Mul,	(i64, i64),	i64)),
		("I64Div",	mk Prim2 (P.I64Div,	(i64, i64),	i64)),
		("I64Mod",	mk Prim2 (P.I64Mod,	(i64, i64),	i64)),
		("I64LSh",	mk Prim2 (P.I64LSh,	(i64, i64),	i64)),
(*
		("I64RShA",	mk Prim2 (P.I64RShA,	(i64, i64),	i64)),
		("I64RShL",	mk Prim2 (P.I64RShL,	(i64, i64),	i64)),
*)
		("I64Neg",	mk Prim1 (P.I64Neg,	i64,		i64)),
		("I64Eq",	mk Prim2 (P.I64Eq,	(i64, i64),	bTy)),
		("I64NEq",	mk Prim2 (P.I64NEq,	(i64, i64),	bTy)),
		("I64Lt",	mk Prim2 (P.I64Lt,	(i64, i64),	bTy)),
		("I64Lte",	mk Prim2 (P.I64Lte,	(i64, i64),	bTy)),
		("I64Gt",	mk Prim2 (P.I64Gt,	(i64, i64),	bTy)),
		("I64Gte",	mk Prim2 (P.I64Gte,	(i64, i64),	bTy)),
		("U64Mul",      mk Prim2 (P.U64Mul,     (i64, i64),     i64)),
		("U64Div",      mk Prim2 (P.U64Div,     (i64, i64),     i64)),
		("U64Lt",       mk Prim2 (P.U64Lt,      (i64, i64),     bTy)),
		("F32Add",	mk Prim2 (P.F32Add,	(f32, f32),	f32)),
		("F32Sub",	mk Prim2 (P.F32Sub,	(f32, f32),	f32)),
		("F32Mul",	mk Prim2 (P.F32Mul,	(f32, f32),	f32)),
		("F32Div",	mk Prim2 (P.F32Div,	(f32, f32),	f32)),
		("F32Neg",	mk Prim1 (P.F32Neg,	f32,		f32)),
		("F32Sqrt",	mk Prim1 (P.F32Sqrt,	f32,		f32)),
		("F32Abs",	mk Prim1 (P.F32Abs,	f32,		f32)),
		("F32Eq",	mk Prim2 (P.F32Eq,	(f32, f32),	bTy)),
		("F32NEq",	mk Prim2 (P.F32NEq,	(f32, f32),	bTy)),
		("F32Lt",	mk Prim2 (P.F32Lt,	(f32, f32),	bTy)),
		("F32Lte",	mk Prim2 (P.F32Lte,	(f32, f32),	bTy)),
		("F32Gt",	mk Prim2 (P.F32Gt,	(f32, f32),	bTy)),
		("F32Gte",	mk Prim2 (P.F32Gte,	(f32, f32),	bTy)),
		("F64Add",	mk Prim2 (P.F64Add,	(f64, f64),	f64)),
		("F64Sub",	mk Prim2 (P.F64Sub,	(f64, f64),	f64)),
		("F64Mul",	mk Prim2 (P.F64Mul,	(f64, f64),	f64)),
		("F64Div",	mk Prim2 (P.F64Div,	(f64, f64),	f64)),
		("F64Neg",	mk Prim1 (P.F64Neg,	f64,		f64)),
		("F64Sqrt",	mk Prim1 (P.F64Sqrt,	f64,		f64)),
		("F64Abs",	mk Prim1 (P.F64Abs,	f64,		f64)),
		("F64Eq",	mk Prim2 (P.F64Eq,	(f64, f64),	bTy)),
		("F64NEq",	mk Prim2 (P.F64NEq,	(f64, f64),	bTy)),
		("F64Lt",	mk Prim2 (P.F64Lt,	(f64, f64),	bTy)),
		("F64Lte",	mk Prim2 (P.F64Lte,	(f64, f64),	bTy)),
		("F64Gt",	mk Prim2 (P.F64Gt,	(f64, f64),	bTy)),
		("F64Gte",	mk Prim2 (P.F64Gte,	(f64, f64),	bTy)),
                ("I32ToI64X",   mk Prim1 (P.I32ToI64X,  i32,            i64)),
                ("I32ToI64",    mk Prim1 (P.I32ToI64,   i32,            i64)),
                ("I32ToF32",    mk Prim1 (P.I32ToF32,   i32,            f32)),
                ("I32ToF64",    mk Prim1 (P.I32ToF64,   i32,            f64)),
                ("I64ToF32",    mk Prim1 (P.I64ToF32,   i64,            f32)),
                ("I64ToF64",    mk Prim1 (P.I64ToF64,   i64,            f64)),
                ("F64ToI32",    mk Prim1 (P.F64ToI32,   f64,            i32)),
		("AdrAddI32",   mk Prim2 (P.AdrAddI32,  (adrTy, i32), adrTy)),
		("AdrAddI64",   mk Prim2 (P.AdrAddI64,  (adrTy, i64), adrTy)),
		("AdrSubI32",   mk Prim2 (P.AdrSubI32,  (adrTy, i32), adrTy)),
		("AdrSubI64",   mk Prim2 (P.AdrSubI64,  (adrTy, i64), adrTy)),
		("AdrLoadI8",   mk Prim1 (P.AdrLoadI8,  adrTy,	        i8)),
		("AdrLoadU8",   mk Prim1 (P.AdrLoadU8,  adrTy,	        i8)),
		("AdrLoadI16",  mk Prim1 (P.AdrLoadI16,	adrTy,	        i16)),
		("AdrLoadU16",  mk Prim1 (P.AdrLoadU16,	adrTy,	        i16)),
		("AdrLoadI32",  mk Prim1 (P.AdrLoadI32,	adrTy,	        i32)),
		("AdrLoadI64",  mk Prim1 (P.AdrLoadI64,	adrTy,	        i64)),
		("AdrLoadF32",  mk Prim1 (P.AdrLoadF32,	adrTy,	        f32)),
		("AdrLoadF64",  mk Prim1 (P.AdrLoadF64,	adrTy,	        f64)),
		("AdrLoadAdr",  mk Prim1 (P.AdrLoadAdr,	adrTy,	        adrTy)),
		("AdrLoad",     mk Prim1 (P.AdrLoad,	adrTy,	        aTy)),
		("AdrStoreI8",  mk Prim2 (P.AdrStoreI8,	(adrTy, i8),	        uTy)),
		("AdrStoreI16", mk Prim2 (P.AdrStoreI16,	(adrTy, i16),	        uTy)),
		("AdrStoreI32", mk Prim2 (P.AdrStoreI32,	(adrTy, i32),	        uTy)),
		("AdrStoreI64", mk Prim2 (P.AdrStoreI64,	(adrTy, i64),	        uTy)),
		("AdrStoreF32", mk Prim2 (P.AdrStoreF32,	(adrTy, f32),	        uTy)),
		("AdrStoreF64", mk Prim2 (P.AdrStoreF64,	(adrTy, f64),	        uTy)),
		("AdrStoreAdr", mk Prim2 (P.AdrStoreAdr,	(adrTy, adrTy),	        uTy)),
		("AdrStore",    mk Prim2 (P.AdrStore,	(adrTy, aTy),	        uTy)),
		("ArrLoadI32",   mk Prim2 (P.ArrLoadI32,	(adrTy, i32),	        i32)),
		("ArrLoadI64",   mk Prim2 (P.ArrLoadI64,	(adrTy, i32),	        i64)),
		("ArrLoadF32",   mk Prim2 (P.ArrLoadF32,	(adrTy, i32),	        f32)),
		("ArrLoadF64",   mk Prim2 (P.ArrLoadF64,	(adrTy, i32),	        f64)),
		("ArrLoad",	   mk Prim2 (P.ArrLoad,	(adrTy, i32),	        f64)),
		("ArrStoreI32",  mk Prim3 (P.ArrStoreI32,	(adrTy, i32, i32),	uTy)),
		("ArrStoreI64",  mk Prim3 (P.ArrStoreI64,	(adrTy, i32, i64),	uTy)),
		("ArrStoreF32",  mk Prim3 (P.ArrStoreF32,	(adrTy, i32, f32),	uTy)),
		("ArrStoreF64",  mk Prim3 (P.ArrStoreF64,	(adrTy, i32, f64),	uTy)),
		("ArrStore",	   mk Prim3 (P.ArrStore,	(adrTy, i32, f64),	uTy)),
		("I32FetchAndAdd", mk Prim2 (P.I32FetchAndAdd,	(i32, i32),		i32)),
		("I64FetchAndAdd", mk Prim2 (P.I32FetchAndAdd,	(i64, i64),		i64)),
		("CAS",		mk Prim3 (P.CAS,	(adrTy, aTy, aTy), aTy)),
		("BCAS",	mk Prim3 (P.BCAS,	(adrTy, aTy, aTy), bTy)),
		("TAS",		mk Prim1 (P.TAS,	bTy,		bTy)),
		("Pause",	mk0 (P.Pause,				uTy)),
		("FenceRead",	mk0 (P.FenceRead,			uTy)),
		("FenceWrite",	mk0 (P.FenceWrite,			uTy)),
		("FenceRW",	mk0 (P.FenceRW,				uTy))
	      ];
	    AtomTable.find tbl
	  end

  end
