(* unify.sml
 *
 * COPYRIGHT (c) 2007 John Reppy (http://www.cs.uchicago.edu/~jhr)
 * All rights reserved.
 *
 * Based on CMSC 22610 Sample code (Winter 2007)
 *)

structure Unify : sig

  (* destructively unify two types; return true if successful, false otherwise *)
    val unify : Types.ty * Types.ty -> bool

  (* nondestructively check if two types are unifiable. *)
    val unifiable : Types.ty * Types.ty -> bool

  (* nondestructively check if two type schemes are unifiable. *)
    val match : (Env.realization_env * Types.ty_scheme * Types.ty_scheme) -> bool

  end = struct

    structure Ty = Types
    structure MV = MetaVar
    structure TU = TypeUtil
    structure TC = TypeClass
  (* type-variable equality assumptions *)
    structure TVA = BinarySetFn (
                        type ord_key = (Types.tyvar * Types.tyvar)
                        fun compare ((tv11, tv12), (tv21, tv22)) = 
			    (case (TyVar.compare(tv11, tv21), TyVar.compare(tv12, tv22))
                              of (EQUAL, c2) => c2
			       | (c1, _) => c1
                            (* end case *))
                        )

  (* context for unification *)
    datatype ctx
      = CTX of {
	     tvAssum : TVA.set,                        (* type-variable equality assumptions *)
	     realizations : Env.realization_env        (* type realizations *)
           }

    fun getRealizationTy (realizations, tyc) = (case Env.RealizationEnv.find(realizations, tyc)
        of SOME (Env.TyDef (Ty.TyScheme ([], ty))) => SOME ty
	 | _ => NONE
        (* end case *))

(* FIXME: add a control to enable this flag *)
    val debugUnify = ref false

  (* does a meta-variable occur in a type? *)
    fun occursIn (mv, ty) = let
	  fun occurs ty = (case TU.prune ty
		 of Ty.ErrorTy => false
		  | (Ty.MetaTy mv') => MV.same(mv, mv')
		  | (Ty.VarTy _) => raise Fail "unexpected type variable"
		  | (Ty.ConTy(args, _)) => List.exists occurs args
		  | (Ty.FunTy(ty1, ty2)) => occurs ty1 orelse occurs ty2
		  | (Ty.TupleTy tys) => List.exists occurs tys
		(* end case *))
	  in
	    occurs ty
	  end

  (* unify two types *)
    fun unifyRC (CTX{tvAssum, realizations}, ty1, ty2, reconstruct) = let
	  val mv_changes = ref []
	  fun assignMV (info, newInfo) = (
		if reconstruct
		  then mv_changes := (info, !info) :: !mv_changes
		  else ();
		info := newInfo)
	(* adjust the depth of any non-instantiated meta-variable that is bound
	 * deeper than the given depth.
	 *)
	  fun adjustDepth (ty, depth) = let
		fun adjust Ty.ErrorTy = ()
		  | adjust (Ty.MetaTy(Ty.MVar{info, ...})) = (case !info
		       of Ty.UNIV d => if (depth < d) then assignMV(info, Ty.UNIV depth) else ()
			| Ty.CLASS _ => ()
			| Ty.INSTANCE ty => adjust ty
		      (* end case *))
		  | adjust (Ty.VarTy _) = raise Fail "unexpected type variable"
		  | adjust (Ty.ConTy(args, _)) = List.app adjust args
		  | adjust (Ty.FunTy(ty1, ty2)) = (adjust ty1; adjust ty2)
		  | adjust (Ty.TupleTy tys) = List.app adjust tys
		in
		  adjust ty
		end
	  fun uni (ty1, ty2) = (case (TU.prune ty1, TU.prune ty2)
		 of (Ty.ErrorTy, ty2) => true
		  | (ty1, Ty.ErrorTy) => true
		  | (Ty.VarTy tv1, Ty.VarTy tv2) => 
		      TVA.member (tvAssum, (tv1, tv2))
		  | (ty, Ty.VarTy tv2) => true
		  | (ty1 as Ty.MetaTy mv1, ty2 as Ty.MetaTy mv2) =>
		      MetaVar.same(mv1, mv2) orelse unifyMV(mv1, mv2)
		  | (Ty.MetaTy mv1, ty2) => unifyWithMV (ty2, mv1)
		  | (ty1, Ty.MetaTy mv2) => unifyWithMV (ty1, mv2)
		  | (Ty.ConTy(tys1, tyc1), Ty.ConTy(tys2, tyc2)) =>
		    (case getRealizationTy(realizations, tyc1)
		      of NONE => (TyCon.same(tyc1, tyc2)) andalso ListPair.allEq uni (tys1, tys2)
		       | SOME ty1 => uni(ty1, ty2)
		    (* end case *))
		  | (Ty.ConTy([], tyc1), ty2) => 
		    (case getRealizationTy(realizations, tyc1)
		      of NONE => false
		       | SOME ty1 => uni(ty1, ty2)
		    (* end case *))
		  | (Ty.FunTy(ty11, ty12), Ty.FunTy(ty21, ty22)) => 
		      uni(ty11, ty21) andalso uni(ty12, ty22)
		  | (Ty.TupleTy tys1, Ty.TupleTy tys2) =>
		      ListPair.allEq uni (tys1, tys2)
		  | _ => false
	       (* end case *))
	(* unify a type with an uninstantiated meta-variable *)
	  and unifyWithMV (ty, mv as Ty.MVar{info, ...}) = let
		fun isClass cls = if TC.isClass(ty, cls)
		      then (assignMV(info, Ty.INSTANCE ty); true)
		      else false
		in
		  case !info
		   of Ty.UNIV d => if (occursIn(mv, ty))
			then false
			else (adjustDepth(ty, d); assignMV(info, Ty.INSTANCE ty); true)
		    | Ty.CLASS cls => if occursIn(mv, ty)
			then false
			else (case cls
			   of Ty.Int => isClass Basis.IntClass
			    | Ty.Float => isClass Basis.FloatClass
			    | Ty.Num => isClass Basis.NumClass
			    | Ty.Order => isClass Basis.OrderClass
			    | Ty.Eq => if TC.isEqualityType ty
				then (assignMV(info, Ty.INSTANCE ty); true)
				else false
			  (* end case *))
		    | _ => raise Fail "impossible"
		  (* end case *)
		end
	  and unifyMV (mv1 as Ty.MVar{info=info1, ...}, mv2 as Ty.MVar{info=info2, ...}) = let
		fun assign (info1, mv2) = (assignMV(info1, Ty.INSTANCE(Ty.MetaTy mv2)); true)
		in
		  case (!info1, !info2)
		   of (Ty.UNIV d1, Ty.UNIV d2) => if (d1 < d2)
			then assign(info2, mv1)
			else assign(info1, mv2)
		    | (Ty.UNIV _, _) => assign(info1, mv2)
		    | (_, Ty.UNIV _) => assign(info2, mv1)
		    | (Ty.CLASS cl1, Ty.CLASS cl2) => (case (cl1, cl2)
			 of (Ty.Int, Ty.Float) => false
			  | (Ty.Float, Ty.Int) => false
			  | (Ty.Int, _) => assign (info2, mv1)
			  | (_, Ty.Int) => assign (info1, mv2)
			  | (Ty.Float, _) => assign (info2, mv1)
			  | (_, Ty.Float) => assign (info1, mv2)
			  | (Ty.Num, _) => assign (info2, mv1)
			  | (_, Ty.Num) => assign (info1, mv2)
			  | (Ty.Order, _) => assign (info2, mv1)
			  | (_, Ty.Order) => assign (info1, mv2)
			  | _ => true
			(* end case *))
		    | _ => raise Fail "impossible"
		  (* end case *)
		end
(*	  and unifyTyScheme (CTX{tvAssum, realizations}, Ty.TyScheme (tvs1, ty1), Ty.TyScheme (tvs2, ty2)) = let
	      (* construct ty-var equality assumptions *)
	      val tvAssum = List.foldl TVA.add' tvAssum (ListPair.zip (tvs1, tvs2) @ ListPair.zip (tvs2, tvs1))
	      val ctx = CTX{tvAssum=tvAssum, realizations=realizations}
              in
	          (List.length tvs1 = List.length tvs2) andalso uni(ty1, ty2)
              end
*)
	  val ty = uni (ty1, ty2)
	  in
	    if reconstruct
	      then List.app (op :=) (!mv_changes)
	      else ();
	    ty
	  end

    fun unify (ty1, ty2) = let
	  val _ = if !debugUnify
		    then print(concat[
			"unify (", TypeUtil.fmt {long=true} ty1, ", ",
			TypeUtil.fmt {long=true} ty2, ")\n"
		      ])
		    else ()
	  val res = unifyRC (CTX{tvAssum=TVA.empty, realizations=Env.RealizationEnv.empty}, ty1, ty2, false)
	  in
	    if !debugUnify
	      then if res
		then print(concat["  = ", TypeUtil.fmt {long=true} ty1, "\n"])
		else print "  FAILURE\n"
	      else ();
	    res
	  end

    fun unifiable (ty1, ty2) = unifyRC (CTX{tvAssum=TVA.empty, realizations=Env.RealizationEnv.empty}, ty1, ty2, true)

    fun match (realizations, Ty.TyScheme (tvs1, ty1), Ty.TyScheme (tvs2, ty2)) = let
	(* construct ty-var equality assumptions *)
	val tvAssum = List.foldl TVA.add' TVA.empty (ListPair.zip (tvs1, tvs2) @ ListPair.zip (tvs2, tvs1))
	val ctx = CTX{tvAssum=tvAssum, realizations=realizations}
        in
	   (List.length tvs1 <= List.length tvs2) andalso unifyRC(ctx, ty1, ty2, true)
	end
			   
  end
