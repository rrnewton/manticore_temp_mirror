(* translate-ptup.sml
 *
 * COPYRIGHT (c) 2008 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 *
 * Here we translate parallel tuples to scheduling primitives. Our translation uses the
 * fast / slow clone technique designed for the Cilk-5 language.
 * 
 * Our translation extends the Cilk-5 technique by adding lazy promotion. That is, we
 * defer any promotions to the slow clone.
 *)

structure TranslatePTup  : sig

  (* An AST to BOM translation of parrays to ropes. *)
    val tr : {
	  env : TranslateEnv.env,
	  es : BOM.exp list
	} -> BOM.exp

  end  = struct

    structure B   = BOM
    structure BTy = BOMTy
    structure BU  = BOMUtil
    structure BTy = BOMTy
    structure BV = BOM.Var
    structure E = TranslateEnv
    structure Lit = Literal

    val findBOMTy = E.findBOMTyByPath
    val findHLOp = E.findBOMHLOpByPath

    fun varOfLambda (B.FB {f, ...}) = f

    val intTy = BTy.T_Raw RawTypes.T_Int
    fun intRhs x = B.E_Const (Literal.Int (Int.toLarge x), intTy)

    fun unitVar () = BV.new("_unit", BTy.unitTy)

  (* create a tuple whose elements are initialized as nil values *)
    fun mkNilTuple (tuple : B.var, tys : BTy.ty list, e : B.exp) : B.exp = let 
	  fun mkLets (binds, e') = List.foldl (fn ((x, e), e') => B.mkLet ([x], e, e')) e' binds
	  fun mk ty_i = let
		val x = BV.new ("x", BTy.T_Any)
		val y = BV.new ("y", BTy.T_Any)
		val v = BV.new ("nil", ty_i)
		in (
		  v,
		  B.mkStmts([
		      ([x], B.E_Const(Lit.unitLit, BTy.T_Any)), 
		      ([y], B.E_Cast (ty_i, x))
		    ], B.mkRet [y])
		) end
	  val nils = List.map mk tys
	  in
	    mkLets (nils, B.mkStmt ([tuple], B.E_Alloc (BTy.T_Tuple (true, tys), List.map #1 nils), e))
	  end

  (* implicit-thread creation *)
    fun mkThread (k, exh) = B.mkHLOp (findHLOp ["ImplicitThread", "thread-no-cancelable"], [k], [exh])
  (* scheduling operations *)
    fun spawnThread (k, exh) = B.mkHLOp (findHLOp ["ImplicitThread", "spawn"], [k], [exh])
    fun removeThread (thread, exh) = B.mkHLOp (findHLOp ["ImplicitThread", "remove-thread"], [thread], [exh])
    local
      fun mkRaiseExn (env, exh) = let
	    val matchExnDCon = (case E.findDCon(env, Basis.exnMatch)
		   of SOME(E.ExnConst matchExnDCon) => matchExnDCon
		    | _ => raise Fail "compiler bug: missing match exception"
		  (* end case *))
	    val matchExn = BV.new("matchExn", BTy.T_TyCon(BOMTyCon.dconTyc matchExnDCon))
	    in
	      B.mkStmt([matchExn], B.E_DCon(matchExnDCon, []), B.mkThrow(exh, [matchExn]))
	    end
    in
    fun mkStop (env, exh) = 
	  B.mkLet([unitVar()], 
		    B.mkHLOp(findHLOp["SchedulerAction", "stop"], [], []),
	    mkRaiseExn(env, exh))
    end

    fun tr {env, es = []} = let
	  val x = BV.new ("x", BTy.unitTy)
	  in
	    B.mkStmt ([x], B.E_Const(Lit.unitLit, BTy.unitTy), B.mkRet [x])
	  end
      | tr {env, es = es as e_0 :: es_1toN} = let
	  val n = List.length es
	  val tys as ty_0 :: _ = List.map (List.hd o BOMUtil.typeOfExp) es
	  val tupleTy = BTy.T_Tuple (false, tys)
	  val slowCloneTupleTy = BTy.T_Tuple (true, tys)
	  val r0 = BV.new ("r0", slowCloneTupleTy)
	  val c0 = BV.new ("c0", BTy.T_Tuple (true, [intTy]))
	  val exh = E.handlerOf env
	  val thunks_1toN = let
		fun mkThunk e_i = let
		      val thunk_i = BV.new("thunk_i", BTy.T_Fun([], [BTy.exhTy], BOMUtil.typeOfExp e_i))
		      val (exh, _) = E.newHandler env
		      in
			B.mkLambda {f = thunk_i, params = [], exh = [exh], body = e_i}
		      end
		in
		  List.map mkThunk es_1toN
		end
	  val thunkVs_1toN = List.map varOfLambda thunks_1toN
	(* store the ith value in the result array *)
	  fun store (i, v_i, r, exh) = let
		val ty_i = BV.typeOf v_i
		val v_i' = BV.new ("v'_" ^ Int.toString i, ty_i)
		in
		  B.mkStmt ([v_i'], B.E_Promote v_i,
		  B.mkStmt ([], B.E_Update (i, r, v_i'),
		    B.mkRet []))
		end
	(* signal that w elements of the tuple have been evaluated *)
	  fun finish (w, r) = let
		val nPrev = BV.new ("nPrev", intTy)
		val nV = BV.new ("n", intTy)
		val wV = BV.new ("w", intTy)
		val c' = BV.new ("c'", BTy.T_Tuple (true, [intTy]))
		val c =  BV.new ("c", BTy.T_Addr intTy)
		in
		  B.mkStmts ([
		      ([c'], B.E_Promote c0),         (* lazy promotion *)
		      ([c], B.E_AddrOf (0, c')),
		      ([nV], intRhs (n - w + 1)),     (* nV is the number of other slow clones *)
		      ([wV], intRhs w),
		      ([nPrev], B.E_Prim (Prim.I32FetchAndAdd (c, wV)))
		    ],
		    B.mkIf (Prim.I32Eq (nV, nPrev), 
		    (* the worker has the complete tuple *)
		      B.mkRet [r],
		    (* other workers are still working *)
		      mkStop (env, exh)))
		end	    
(* FIXME: handle exceptions as defined by our sequential semantics *)
	(* we create n - 1 slow clones *)
	  val slowClones_1toN = 
		List.tabulate (n - 1,
		  fn i => BV.new ("slowCloneThread_" ^ Int.toString (i + 1), 
		      findBOMTy ["ImplicitThread", "thread"]))
	  fun mkSlowClones eNext = let
	      (* evaluate the ith thunk and store the result in the result tuple *)
		  fun force (i, thunk_i, r, exh) = let
			val BTy.T_Fun (_, _, [ty_i]) = BV.typeOf thunk_i
			val v_i = BV.new ("v_" ^ Int.toString i, ty_i)
			in
			  B.mkLet ([v_i], B.mkApply (thunk_i, [], [exh]), store (i, v_i, r, exh))
			end
		  fun mkSlowClone (0, [], []) = eNext
		    | mkSlowClone (i, thunk_i :: thunks, slowCloneThread :: slowClones_1toN) = let
			val slowClone_i = BV.new ("slowClone_" ^ Int.toString i, BTy.T_Cont [BTy.unitTy])
			val r = BV.new ("r", slowCloneTupleTy)
			in
			  B.mkCont (B.mkLambda {f = slowClone_i, params = [unitVar ()], exh = [], 
						body = 
						B.mkStmt ([r], B.E_Promote r0,            (* lazy promotion *)
							  B.mkLet ([], force (i, thunk_i, r, exh), finish (1, r)))},
				    B.mkLet ([slowCloneThread], mkThread (slowClone_i, exh), 
					     B.mkLet ([], spawnThread (slowCloneThread, exh),
						      mkSlowClone (i - 1, thunks, slowClones_1toN))))
			end
		    | mkSlowClone _ = raise Fail "impossible"
		  in
		  (* put slow clones on the queue in reverse order (right to left) *)
		    mkSlowClone (n - 1, List.rev (List.map varOfLambda thunks_1toN), List.rev slowClones_1toN)
		  end
	(* the fast clone evaluates the elements of the tuple in sequential order until either all
	 * the elements have evaluated or all elements to the right have been stolen.
	 *)
	  fun fastClone (_, [], [], vs) = let
		val tuple = BV.new ("tuple", tupleTy)
		in
		  B.mkStmt ([tuple], B.E_Alloc (tupleTy, List.rev vs), B.mkRet [tuple])
		end
	    | fastClone (i, thunk_i :: thunks, slowCloneThread_i :: slowClones_1toN, vs) = let
		val BTy.T_Fun (_, _, [ty_i]) = BV.typeOf thunk_i
		val v_i = BV.new ("v_" ^ Int.toString i, ty_i)
		val notStolen_i = BV.new ("notStolen_" ^ Int.toString i, BOMTyUtil.boolTy)
		val r = BV.new ("r", slowCloneTupleTy)
		in
		  B.mkLet([notStolen_i], removeThread (slowCloneThread_i, exh),
		    BOMUtil.mkBoolCase (notStolen_i,
		      B.mkLet ([v_i], B.mkApply (thunk_i, [], [exh]),
			fastClone (i + 1, thunks, slowClones_1toN, v_i :: vs)),
		    (* switch to the slow clone *)
		      B.mkStmt ([r], B.E_Promote r0,         (* lazy promotion *)
			ListPair.foldlEq
			  (fn (i, v_i, e) => B.mkLet ([], store (i, v_i, r, exh), e)) 
			    (finish (i, r))
			      (List.tabulate (List.length vs, fn i => i), List.rev vs))))
		end
	    | fastClone _ = raise Fail "impossible"
	  val one = intRhs 1
	  val oneV = BV.new ("one", intTy)
	  in
	    mkNilTuple (r0, tys,
			  B.mkStmts ([
			  ([oneV], one),
			  ([c0], B.E_Alloc (BTy.T_Tuple (true, [intTy]), [oneV]))
			  ],
				     B.mkFun (thunks_1toN, 
					      mkSlowClones (
					      let
						  val v_0 = BV.new ("v_0", ty_0)
					      in
						  B.mkLet ([v_0], e_0,
							   fastClone (1, thunkVs_1toN, slowClones_1toN, [v_0]))
					      end))))
	  end

  end
