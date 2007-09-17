(* translate-types.sml
 *
 * COPYRIGHT (c) 2007 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 *)

structure TranslateTypes : sig

    val tr : TranslateEnv.env * AST.ty -> BOM.ty
    val trScheme : TranslateEnv.env * AST.ty_scheme -> BOM.ty

    val trDataCon : TranslateEnv.env * AST.dcon -> TranslateEnv.con_bind

  end = struct

    structure Ty = Types;
    structure BTy = BOMTy
    structure BTyc = BOMTyCon
    structure E = TranslateEnv

    fun tr (env, ty) = let
	  fun tr' ty = (case TypeUtil.prune ty
		 of Ty.ErrorTy => raise Fail "unexpected ErrorTy"
		  | Ty.MetaTy _ => BTy.T_Any (* can this happen? *)
		  | Ty.ClassTy _ => raise Fail "unresolved overload"
		  | Ty.VarTy _ => BTy.T_Any
		  | Ty.ConTy(tyArgs, tyc) => (
		      case TranslateEnv.findTyc (env, tyc)
		       of SOME ty => ty
			| NONE => trTyc (env, tyc)
		      (* end case *))
		  | Ty.FunTy(ty1, ty2) => BTy.T_Fun([tr' ty1], [BTy.exhTy], [tr' ty2])
		  | Ty.TupleTy [] => BTy.unitTy
		  | Ty.TupleTy tys => BTy.T_Tuple(false, List.map tr' tys)
		(* end case *))
	  in
	    tr' ty
	  end

    and trTyc (env, Ty.AbsTyc{name, ...}) = raise Fail("Unknown abstract type " ^ Atom.toString name)
      | trTyc (env, tyc as Ty.DataTyc{name, cons, ...}) = let
	(* insert a placeholder representation for tyc to avoid infinite loops *)
	  val _ = E.insertTyc (env, tyc, BTy.T_Any)
	(* partition constructors into constants and constructor function lists *)
	  val (consts, conFuns) =
		List.partition
		  (fn (Ty.DCon{argTy=NONE, ...}) => true | _ => false)
		    (! cons)
	(* create the data constructor *)
	  val nConsts = List.length consts
	  val dataTyc as BTy.DataTyc{rep, kind, ...} =
		BOMTyCon.newDataTyc (Atom.toString name, nConsts)
	  fun setRep (ty, k) = (rep := ty; kind := k)
	(* assign representations for the constants *)
	  fun assignConstRep (dc, i) = (
		E.insertConst (env, dc, i, BTy.T_Enum(Word.fromInt nConsts - 0w1));
		i + 0w1)
	  val _ = List.foldl assignConstRep 0w0 consts
	(* assign representations for the constructor functions *)
	  val newDataCon = BTyc.newDataCon dataTyc
	  fun mkDC (dc, rep, tys) = let
		val dc' = newDataCon (DataCon.nameOf dc, rep, tys)
		in
		  E.insertDCon (env, dc, dc')
		end
	(* translate the argument type of a data constructor *)
	  fun trArgTy dc = tr (env, valOf (DataCon.argTypeOf dc))
	  in
	    case (consts, conFuns)
	     of (_::_, []) => setRep (BTy.T_Enum(Word.fromInt nConsts - 0w1), BTy.K_UNBOXED)
	      | ([], [dc]) => let
		  val ty = trArgTy dc
		  in
		    setRep (ty, BOMTyUtil.kindOf ty);
		    mkDC (dc, BTy.Transparent, [ty])
		  end
	      | (_, [dc]) => (
		  case bomKindOfType (env, valOf(DataCon.argTypeOf dc))
		   of BTy.K_BOXED => mkDC (dc, BTy.Transparent, [trArgTy dc])
		    | _ => (* need to use singleton tuple to represent data constructor *)
			mkDC (dc, BTy.Tuple, [BTy.T_Tuple(false, [trArgTy dc])])
		  (* end case *))
	      | ([], _) => raise Fail ""
	      | (_, _) => raise Fail ""
	    (* end case *);
	    E.insertTyc (env, tyc, BTy.T_TyCon dataTyc);
	    BTy.T_TyCon dataTyc
	  end

  (* return the BOM kind of an AST type; this code looks at the top-level structure
   * of the type to determine the kind.
   *)
    and bomKindOfType (env, ty) = (case ty
	   of (Ty.FunTy _) => BTy.K_BOXED
	    | (Ty.TupleTy []) => BTy.K_UNBOXED
	    | (Ty.TupleTy _) => BTy.K_BOXED
	    | (Ty.ConTy(_, tyc)) => (
		case TranslateEnv.findTyc (env, tyc)
		 of SOME ty => BOMTyUtil.kindOf ty
		  | NONE => BOMTyUtil.kindOf (trTyc (env, tyc))
		(* end case *))
	    | _ => BTy.K_UNIFORM
	  (* end case *))

    fun trScheme (env, Ty.TyScheme(_, ty)) = tr (env, ty)

    fun trDataCon (env, dc as Ty.DCon{owner, ...}) = (case E.findDCon(env, dc)
	   of SOME dc' => dc'
	    | NONE => (ignore (trTyc(env, owner)); trDataCon (env, dc))
	  (* end case *))

  end
