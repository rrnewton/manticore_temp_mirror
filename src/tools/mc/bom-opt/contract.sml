(* contract.sml
 *
 * COPYRIGHT (c) 2007 The Manticore Project (http://manticore.cs.uchicago.edu/)
 * All rights reserved.
 *
 * An Jim-Appel-style contraction phase for the BOM representation.
 * The contraction optimizations include:
 *
 *      - application of functions that are called exactly once
 *      - elimination of unused variables that are bound to "pure" expressions.
 *)

structure Contract : sig

    type flags = {
        removeExterns : bool    (* if true, remove unused externs. *)
      }

    val contract : flags -> BOM.module -> BOM.module

  end = struct

    structure B = BOM
    structure BV = B.Var
    structure BTy = BOMTy
    structure Lit = Literal
    structure C = Census
    structure U = BOMUtil
    structure ST = Stats

    type flags = {
        removeExterns : bool    (* if true, remove unused externs. *)
      }

  (********** Counters for statistics **********)
    val cntUnusedStmt           = ST.newCounter "contract:unused-stmt"
    val cntLetRename            = ST.newCounter "contract:let-rename"
    val cntLetElim              = ST.newCounter "contract:let-elim"
    val cntLetFloat             = ST.newCounter "contract:let-float"
    val cntUnusedCast           = ST.newCounter "contract:unused-cast"
    val cntIdCast               = ST.newCounter "contract:identity-cast"
    val cntUnusedSelect         = ST.newCounter "contract:unused-select"
    val cntSelectConst          = ST.newCounter "contract:select-const"
    val cntReallocElim          = ST.newCounter "contract:realloc-elim"
    val cntDeadFun              = ST.newCounter "contract:dead-fun"
    val cntDeadRecFun           = ST.newCounter "contract:dead-rec-fun"
    val cntDeadCont             = ST.newCounter "contract:dead-cont"
    val cntEta                  = ST.newCounter "contract:eta"
    val cntIfReduce             = ST.newCounter "contract:if-reduce"
    val cntTrivCase             = ST.newCounter "contract:triv-case"
    val cntCaseConst            = ST.newCounter "contract:case-const"
    val cntCaseIfFold		= ST.newCounter "contract:case-if-fold"
    val cntBeta                 = ST.newCounter "contract:beta"
    val cntBetaCont             = ST.newCounter "contract:beta-cont"
    val cntUnusedCFun           = ST.newCounter "contract:unused-cfun"
    val firstCounter            = cntUnusedStmt
    val lastCounter             = cntUnusedCFun
  (* these counters track the number of contraction phases/iterations *)
    val cntPhases               = ST.newCounter "contract:phases"
    val cntIters                = ST.newCounter "contract:iterations"


  (********** Get variable info **********)
    fun bindingOf (VarRep.V{kind, ...}) = !kind
    fun setBinding (VarRep.V{kind, ...}, b) = kind := b
    fun setBindings ([x], b) = setBinding(x, b)
      | setBindings _ = ()
    fun useCntRef (VarRep.V{useCnt, ...}) = useCnt
    fun useCntOf v = !(useCntRef v)
    val appCntRef = BV.appCntRef
    val appCntOf = BV.appCntOf
    val combineAppUseCnts = BV.combineAppUseCnts

  (* functions to update census counts *)
    fun inc x = BV.addToCount(x, 1)
    fun dec x = BV.addToCount(x, ~1)
    val dec' = List.app dec
    fun unused x = (useCntOf x = 0)

  (* support for recording that a function has been inlined.  Note that we
   * need to distinguish between inlined and dead functions (even though
   * both have zero use counts), since when a function is inlined its body
   * has been copied, but when a function is dead, the variables it references
   * must have their counts decreased.
   *)
    fun markInlined (VarRep.V{kind, ...}) = kind := B.VK_None
    fun isInlined (VarRep.V{kind = ref B.VK_None, ...}) = true
      | isInlined _ = false

    fun += (r, i : int) = r := !r + i
    fun -= (r, i : int) = r := !r - i
    infix += -=


  (********** Continuation IDs **********)
    val {clrFn=clrKID, getFn=getKID, setFn=setKID, ...} = BV.newProp (fn _ => ~1)


  (********** effect analysis **********)
    fun pureRHS (B.E_Update _) = false
      | pureRHS (B.E_Prim p) = PrimUtil.isPure p
      | pureRHS (B.E_CCall(cf, _)) = (case BV.kindOf cf
	   of B.VK_CFun cf => CFunctions.isPure cf
	    | _ => false
	  (* end case *))
      | pureRHS (B.E_VPStore _) = false
      | pureRHS _ = true

    local
      val {peekFn, setFn, ...} = ProgPt.newProp (fn _ => false)
    in
    fun pureExp (B.E_Pt(ppt, e)) = (case peekFn ppt
           of SOME isPure => isPure
            | NONE => let
                val isPure = (case e
                       of B.E_Let(_, e1, e2) => pureExp e1 andalso pureExp e2
                        | B.E_Stmt(_, rhs, e) => pureRHS rhs andalso pureExp e
                        | B.E_Fun(_, e) => pureExp e
                        | B.E_Cont(_, e) => pureExp e
                        | B.E_If(cond, e1, e2) =>
			    CondUtil.isPure cond andalso pureExp e1 andalso pureExp e2
                        | B.E_Case(x, cases, dflt) =>
                            List.all (fn (_, e) => pureExp e) cases
                            andalso (case dflt of SOME e => pureExp e | _ => true)
                        | B.E_Apply(f, args, rets) => false
                        | B.E_Throw(k, args) => false
                        | B.E_Ret xs => true
                        | B.E_HLOp(hlop, _, _) => HLOp.isPure hlop
                      (* end case *))
                in
                  setFn(ppt, isPure);
                  isPure
                end
          (* end case *))
    end (* local *)


  (********** Contraction **********)

  (* extend the environment with a mapping from the "toVars" to the "fromVars" (i.e.,
   * instances of a ftoVarromVar will be replaced with the corresponding fromVar),
   * inserting type casts as necessary
   *)
    fun extendWithCasts {env, fromVars, toVars} = let
        (* FIXME -- Do this right! *)
          fun needsCast (fromTy, toTy) = (case fromTy
                 of BTy.T_Any => not (BOMTyUtil.equal (BTy.T_Any, toTy)) 
                  | BTy.T_Tuple(b, ts) => (case toTy
                       of BTy.T_Tuple (b', ts') => ListPair.exists needsCast (ts, ts')
                        | _ => false
                      (* end case *))
                  | _ => false
                (* end case *))
          fun mkCasts ([], [], fromVars', casts) = (List.rev fromVars', List.rev casts)
            | mkCasts (_::_, [], _, _) = raise Fail "more fromVars than toVars" 
            | mkCasts ([], _::_, _, _) = raise Fail "more toVars than fromVars"
            | mkCasts (fromVar::fromVars, toVar::toVars, fromVars', casts) = let
                val fromTy = BV.typeOf fromVar
                val toTy = BV.typeOf toVar
                in
                  if not (needsCast (fromTy, toTy))
                    then mkCasts (fromVars, toVars, fromVar::fromVars', casts)
                    else let
                      val name = let val x = BV.nameOf fromVar
                            in 
                              concat ["_cast", (if String.isPrefix "_" x then "" else "_"), x]
                            end
                      val c = BV.new (name, toTy)
                      val _ = Census.incUseCnt c (* because bind will decrement the count *)
                      val cast = ([c], B.E_Cast(toTy, fromVar))
                      in
                        mkCasts (fromVars, toVars, c::fromVars', cast::casts)
                      end
                end
          val (fromVars',casts) = mkCasts (fromVars, toVars, [], [])
          fun bind (fromVar', toVar, env) = (
                BV.combineAppUseCnts (fromVar', toVar);
                dec fromVar';
                U.extend (env, toVar, fromVar'))
          val env' = ListPair.foldl bind env (fromVars', toVars)
          in
	    (env', casts)
          end

  (* we use this global to hold the eta flag that the contract function gets
   * as an argument.  It isn't reentrant, but a lot easier!
   *)
    val doEta = ref false

  (* try to eta contract a function definition *)
    fun etaContract (B.FB{f, params, exh, body}) =
          if !doEta
            then (case body
               of (B.E_Pt(_, B.E_Apply(g, args, rets))) => let
                    fun eq ([], []) = true
                      | eq (x::xs, y::ys) = BV.same(x, y) andalso eq(xs, ys)
                      | eq _ = false
                    in
                      if not(BV.same(f, g))
                      andalso eq(params, args)
                      andalso eq(exh, rets)
                        then SOME g
                        else NONE
                    end
                | _ => NONE
              (* end case *))
            else NONE

    datatype const_fold_result = datatype PrimContract.const_fold_result

  (* contract a pure RHS form; we assume that x is used and that the variables in
   * the RHS have already been renamed.
   *)
    fun doPureRHS (env, x, rhs) = (case rhs
           of B.E_Select(i, y) => (case bindingOf y
                 of B.VK_RHS(B.E_Alloc(BTy.T_Tuple(false, _), ys)) => let
                      val z = List.nth(ys, i)
                      val (env, casts) = extendWithCasts {env = env, fromVars = [z], toVars = [x]}
                      in
                        ST.tick cntSelectConst;
                        dec y; inc z;
                        OK(casts, env)
                      end
                  | _ => FAIL
                (* end case *))
            | B.E_Alloc(BTy.T_Tuple(false, tys), z::zs) => (case bindingOf z
                 of B.VK_RHS(B.E_Select(0, tpl)) => (case BV.typeOf tpl
                       of BTy.T_Tuple(false, tys') => let
                            fun chk (_, []) = true
                              | chk (i, z::zs) = (case bindingOf z
                                   of B.VK_RHS(B.E_Select(j, tpl')) =>
                                        (i = j) andalso BV.same(tpl, tpl') andalso chk(i+1, zs)
                                    | _ => false
                                  (* end case *))
                            val arity = List.length tys
                            in
                              if (arity = List.length tys')
                              andalso (arity = List.length zs+1)
                              andalso chk(1, zs)
                                then (
                                (* alloc(#0 tpl, #1 tpl, ..., #n tpl) ==> tpl *)
                                  ST.tick cntReallocElim;
                                  dec' (z::zs);
                                  useCntRef tpl += useCntOf x;
                                  OK([], U.extend(env, x, tpl)))
                                else FAIL
                            end
                        | _ => FAIL
                      (* end case *))
                  | _ => FAIL
                (* end case *))
            | B.E_Prim p => PrimContract.contract (env, x, p)
            | _ => FAIL
          (* end case *))

  (* project out the case that matches the given data constructor or literal.  This
   * function returns NONE if none of the cases match.
   *)
    local
      fun match pred = let
	    fun test (_, []) = NONE
	      | test (prefix, (pat, e)::r) = (case pred pat
		   of SOME params => SOME{
			  params = params, act = e,
			  other = List.revAppend(prefix, r)
			}
		    | NONE => test ((pat, e)::prefix, r)
		  (* end case *))
	    in
	      fn cases => test ([], cases)
	    end
    in
    fun matchDC dc = match
	  (fn (B.P_DCon(dc', params)) => if BOMTyCon.dconSame(dc, dc') then SOME params else NONE
	    | _ => NONE)
    fun matchLit lit = match
	  (fn (B.P_Const(lit', _)) => if Literal.same(lit, lit') then SOME[] else NONE
	    | _ => NONE)
    end (* local *)

    fun doExp (env, B.E_Pt(_, t), kid) = (case t
           of B.E_Let(lhs, rhs, e) =>
                if List.all unused lhs andalso pureExp rhs
                  then (
                    ST.tick cntLetElim;
                    C.deleteWithRenaming (env, rhs);
                    doExp (env, e, kid))
                  else let
                          val e' = doExp(env, rhs, kid+1)
                      in
                          if (List.all unused lhs andalso pureExp rhs)
                          then (
                              ST.tick cntLetElim;
                              C.deleteWithRenaming (env, rhs);
                              e')
                          else (
                              case e'
                               of B.E_Pt(_, B.E_Ret ys) => let
                                      (* let lhs = ys in e ==> e[ys/lhs] *)
                                      val (env',casts) = extendWithCasts {env = env, fromVars = ys, toVars = lhs}
                                  in
                                      ST.tick cntLetRename;
                                      B.mkStmts (casts, doExp (env', e, kid))
                                  end
                                | B.E_Pt(_, B.E_Let(xs, e1, e2)) => (
                                  (* let lhs = (let xs = e1 in e2) in e ==> let xs = e1 let lhs = e2 in e *)
                                  ST.tick cntLetFloat;
                                  setBindings (lhs, B.VK_Let e2);
                                  B.mkLet(xs, e1, B.mkLet(lhs, e2, doExp (env, e, kid))))
                                | B.E_Pt(_, B.E_Stmt(xs, rhs, e2)) => (
                                  ST.tick cntLetFloat;
                                  setBindings (lhs, B.VK_Let e2);
                                  B.mkStmt(xs, rhs, B.mkLet(lhs, e2, doExp (env, e, kid))))
                                | B.E_Pt(_, B.E_Fun(fbs, e2)) => (
                                  ST.tick cntLetFloat;
                                  setBindings (lhs, B.VK_Let e2);
                                  B.mkFun(fbs, B.mkLet(lhs, e2, doExp (env, e, kid))))
                                | rhs => (
                                  setBindings (lhs, B.VK_Let rhs);
                                  B.mkLet(lhs, rhs, doExp(env, e, kid)))
                              (* end case *))
                      end
            | B.E_Stmt([x], rhs, e) => let
                val rhs = U.substRHS(env, rhs)
                val _ = setBinding(x, B.VK_RHS rhs)
                fun tryContract () = if unused x
                      then (
                        ST.tick cntUnusedStmt;
                        U.appRHS dec rhs;
                        true)
                      else false
                in
                  if pureRHS rhs
                    then if tryContract()
                      then doExp(env, e, kid)
                      else let
                        val res = doPureRHS(env, x, rhs)
                        in
                          case res
                           of OK([], env) => doExp(env, e, kid)
                            | OK(binds, env) => if tryContract()
                                then e
                                else B.mkStmts(binds, doExp(env, e, kid))
                            | FAIL => B.mkStmt([x], rhs, doExp(env, e, kid))
                          (* end case *)
                        end
                    else B.mkStmt([x], rhs, doExp(env, e, kid))
                end
            | B.E_Stmt(lhs, rhs, e) => let
                val rhs = U.substRHS(env, rhs)
                in
                  setBindings(lhs, B.VK_RHS rhs);
                  B.mkStmt(lhs, rhs, doExp(env, e, kid))
                end
            | B.E_Fun([fb as B.FB{f, params, exh, body}], e) => let
                  fun deadFun () = (
                        ST.tick cntDeadFun;
                        C.deleteWithRenaming (env, body))
                (* reduce the function body and its scope *)
                  fun reduceRest () = let
                        val e' = doExp (env, e, kid)
                        in
                          if (isInlined f)
                            then e'
                          else if (useCntOf f = 0)
                            then (deadFun(); e')
                            else let
                              val fb' = doFunBody(env, fb, kid)
                              in
                                case etaContract fb'
                                 of NONE => B.mkFun([fb'], e')
                                  | (SOME g) => (
                                      ST.tick cntEta;
                                    (* adjust counts of g *)
                                      useCntRef g += (useCntOf f - 1);
                                      appCntRef g += (appCntOf f - 1);
                                    (* replace f with g in e' *)
                                      U.substExp(U.singleton(f, g), e'))
                                (* end case *)
                              end
                          end
                  in
                    case (useCntOf f)
                     of 0 => (deadFun(); doExp (env, e, kid))
                      | 1 => if (appCntOf f = 1)
                          then let
                            val e' = doExp (env, e, kid)
                            in
                              if not(isInlined f)
                                then (
                                  ST.tick cntDeadRecFun;
                                  C.deleteWithRenaming (env, body))
                                else ();
                              e'
                            end
                          else reduceRest()
                      | _ => reduceRest()
                    (* end case *)
                  end
            | B.E_Fun(fbs, e) => let
                (* check to see if a function is dead and do the bookkeeping
                 * if it is.
                 *)
                  fun deadFun (lambda as B.FB{f, body, ...}) = if (useCntOf f = 0)
                        then (
                          ST.tick cntDeadFun;
                          C.deleteWithRenaming (env, body);
                          NONE)
                        else SOME lambda
                (* check to see if a function has been inlined or is dead *)
                  fun deadFun' (lambda as B.FB{f, ...}) =
                        if (isInlined f)
                          then NONE
                          else deadFun lambda
                (* process a function body, but skip those that are going to
                 * be eliminated (i.e., have zero use counts).
                 *)
                  fun doFB (fb as B.FB{f, ...}) = if (useCntOf f = 0)
                        then fb
                        else doFunBody (env, fb, kid)
                  in
                    case List.mapPartial deadFun fbs
                     of [] => doExp (env, e, kid)
                      | fbs => let
                          val e' = doExp(env, e, kid)
                          val fbs = List.mapPartial deadFun' fbs
                          val fbs = List.map doFB fbs
                          in
(** NOTE: this code needs to be modified to also support etaContraction, but
** I'm not sure how to handle the renaming (perhaps as a second pass?).
** [jhr; 2000-05-02]
**)
                            case List.mapPartial deadFun' fbs
                             of [] => e'
                              | fbs => B.mkFun(fbs, e')
                            (* end case *)
                          end
                    (* end case *)
                  end
            | B.E_Cont(B.FB{f, params, body, ...}, e) => let
                (* check to see if a continuation is dead and do the bookkeeping
                 * if it is.
                 *)
                  fun deadCont () = if (useCntOf f = 0)
                        then (
                          ST.tick cntDeadCont;
                          C.deleteWithRenaming (env, body);
                          true)
                        else false
                (* check to see if a continuation has been inlined or is dead *)
                  fun deadCont' () = (isInlined f) orelse deadCont ()
                  in
                    if deadCont()
                      then doExp (env, e, kid)
                      else let
                      (* record a bogus kid to avoid recursive inlining *)
                        val _ = setKID(f, ~1)
                        val body' = doExp(env, body, kid)
                        val fb' = B.FB{f=f, params=params, exh=[], body=body'}
                      (* reset the kind of f to reflect the contracted body *)
                        val _ = BV.setKind (f, B.VK_Cont fb');
                      (* we record the kid as a property of f, so that we
                       * know when it is correct to inline a throw to f
                       * in the expression e.
                       *)
                        val _ = setKID(f, kid)
                        val e' = doExp(env, e, kid)
                        in
                          clrKID f;  (* clear KID property *)
                          if deadCont'()
                            then e'
                            else B.mkCont(fb', e')
                        end
                  end
            | B.E_If(cond, e1, e2) => let
                val cond = CondUtil.map (U.subst env) cond
		fun reduce (keepExp, deleteExp) = (
		      ST.tick cntIfReduce;
		      C.deleteWithRenaming(env, deleteExp);
		      doExp(env, keepExp, kid))
                in
                  case CondContract.contract cond
		   of CondContract.UNKNOWN => B.mkIf(cond, doExp(env, e1, kid), doExp(env, e2, kid))
		    | CondContract.TRUE => reduce (e1, e2)
		    | CondContract.FALSE => reduce (e2, e1)
		  (* end case *)
                end
            | B.E_Case(x, [], SOME e) => let
              (* eliminate a trivial case *)
                val x = U.subst env x
                in
                  ST.tick cntTrivCase;
                  useCntRef x -= 1;
                  doExp (env, e, kid)
                end
            | B.E_Case(x, cases, dflt) => let
                val x = U.subst env x
                fun doCase (pat, e) = (pat, doExp(env, e, kid))
		fun doit () = B.mkCase(x,
		      List.map doCase cases,
		      Option.map (fn e => doExp(env, e, kid)) dflt)
		fun deleteCase (_, e) = C.deleteWithRenaming(env, e)
		fun deleteDflt () = Option.app (fn e => C.deleteWithRenaming(env, e)) dflt
	      (* reduce to a single matched case *)
		fun reduce (args, matchedCase) = (
		      ST.tick cntCaseConst;
		      dec x;
		      case matchedCase
		       of SOME{params, act, other} => let
			    val (env, casts) = extendWithCasts {
				    env = env, fromVars = args, toVars = params
				  }
			    in
			      List.app deleteCase other;
			      deleteDflt ();
			      List.app inc args;
			      B.mkStmts (casts, doExp(env, act, kid))
			    end
			| NONE => (
			    List.app deleteCase cases;
			    doExp(env, valOf dflt, kid))
		      (* end case *))
                in
		  case bindingOf x
		   of B.VK_Let(B.E_Pt(_, B.E_If(cond, e1, e2))) => let
		      (* check for the situation where we are pattern matching
		       * on the result of an if-then-else that has constant-valued
		       * arms.  This situation comes up with the conditional operators
		       * in the basis.
		       *)
(* FIXME: this code does not handle the situation where the default case is the one matching
 * one of the arms of the if!
 *)
			fun asDCon (cases, B.E_Pt(_, e)) = (case e
			       of B.E_Stmt([x], B.E_DCon(dc, args), B.E_Pt(_, B.E_Ret[y])) =>
				    if BV.same(x, y)
				      then (case matchDC dc cases
					 of SOME{params, act, other} =>
					      SOME{args=args, params=params, act=act, other=other}
					  | NONE => NONE
					(* end case *))
				      else NONE
				| _ => NONE
			      (* end case *))
			in
			  case asDCon (cases, e1)
			   of SOME{args=args1, params=params1, act=act1, other} => (case asDCon (other, e2)
				 of SOME{args=args2, params=params2, act=act2, other} => let
				      val (env1, casts1) = extendWithCasts {
					      env = env, fromVars = args1, toVars = params1
					    }
				      val (env2, casts2) = extendWithCasts {
					      env = env, fromVars = args2, toVars = params2
					    }
				      in
					ST.tick cntCaseIfFold;
				        dec x;
					CondUtil.app inc cond;
					List.app deleteCase other;
					deleteDflt ();
					List.app inc args1;
					List.app inc args2;
					B.mkIf(cond,
					  B.mkStmts(casts1, doExp(env1, act1, kid)),
					  B.mkStmts(casts2, doExp(env2, act2, kid)))
				      end
				  | _ => doit ()
				(* end case *))
			    | _ => doit ()
			  (* end case *)
			end
		    | B.VK_RHS(B.E_Const(lit, ty)) => reduce ([], matchLit lit cases)
		    | B.VK_RHS(B.E_DCon(dc, args)) => reduce (args, matchDC dc cases)
		    | _ => doit()
		  (* end case *)
                end
            | B.E_Apply(f, args, rets) => let
                val f = U.subst env f
                val args = U.subst' (env, args)
                val rets = U.subst' (env, rets)
                in
                  case bindingOf f
                   of B.VK_Fun(B.FB{params, exh, body, ...}) =>
                        if (useCntOf f = 1)
                          then ( (* beta-reduce function with single call site *)
                            markInlined f;
                            ST.tick cntBeta;
                            appCntRef f -= 1;
                            useCntRef f -= 1;
                            inlineApply {
                                env = env, kid = kid,
                                args = rets@args, params = exh@params,
                                body = body
                              })
                          else B.mkApply(f, args, rets)
                    | _ => B.mkApply(f, args, rets)
                  (* end case *)
                end
            | B.E_Throw(k, args) => let
                val k = U.subst env k
                val args = U.subst' (env, args)
                in
                  case bindingOf k
                   of B.VK_Cont(B.FB{params, body, ...}) =>
                        if (useCntOf k = 1) andalso (kid = getKID k)
                          then ( (* beta-reduce continuation with single throw site *)
                            markInlined k;
                            ST.tick cntBetaCont;
                            appCntRef k -= 1;
                            useCntRef k -= 1;
                            inlineApply {
                                env = env, kid = kid,
                                args = args, params = params,
                                body = body
                              })
                          else B.mkThrow(k, args)
                    | _ => B.mkThrow(k, args)
                  (* end case *)
                end
            | B.E_Ret xs => B.mkRet(U.subst'(env, xs))
            | B.E_HLOp(hlop, args, rets) =>
                B.mkHLOp(hlop, U.subst'(env, args), U.subst'(env, rets))
          (* end case *))

  (* contract the body of a function.  Prior to doing so, we null out the
   * function variable's binding so that we avoid infinite unwinding.
   *)
    and doFunBody (env, lambda as B.FB{f, params, exh, body}, kid) = let
          val body' = (
                setBinding (f, B.VK_None);
                doExp (env, body, kid+1))
          val lambda' = B.FB{f=f, params=params, exh=exh, body=body'}
          in
            setBinding (f, B.VK_Fun lambda');
            lambda'
          end

  (* inline an application of the function "\params.body".  args is the list of actuals and
   * params is the list of formals.
   *)
    and inlineApply {env : BOMUtil.subst, kid, args, params, body : BOM.exp} = let
          val (env', casts) = extendWithCasts {env = env, fromVars = args, toVars = params}
          in
            B.mkStmts (casts, doExp (env', body, kid))
          end

(*    fun contract _ module =  module*)

    fun contract (flags : flags) (module as B.MODULE{name, externs, hlops, rewrites, body}) = let
          fun ticks () = ST.sum {from = firstCounter, to = lastCounter}
          fun loop (body, prevSum, prevFloats) = let
                val _ = ST.tick cntIters
                val body = doFunBody (U.empty, body, 0)
                val sum = ticks()
                fun needsFloat() = let
                    val letFloats = ST.count cntLetFloat
                    val netFloats = letFloats-prevFloats
                    val netTicks = (sum-prevSum)
                in
                    ((Real.fromInt(netFloats))/Real.fromInt(netTicks) > 0.8)
                end
                in
(*DEBUG*
print(concat["contract: ", Int.toString(sum - prevSum), " ticks\n"]);
if ((sum-prevSum < 4) andalso (sum-prevSum > 0)) then (
    print "******************** after one iteration of contract ********************\n";
    PrintBOM.print(B.MODULE{name=name, externs=externs, hlops=hlops, body=body, rewrites=rewrites}))
  else ();
*DEBUG*)
                  if (prevSum <> sum)
                    then (if needsFloat()
                          then loop (LetFloat.denestLambda(body, true), sum, ST.count cntLetFloat)
                          else loop (body, sum, ST.count cntLetFloat))
                    else body
                end
          val body = LetFloat.denestLambda(body, true)
          val body = loop (body, ticks(), ST.count cntLetFloat)
        (* remove unused externs *)
          fun removeUnusedExtern cf = if unused(CFunctions.varOf cf)
                then (
                  ST.tick cntUnusedCFun;
                  false) 
                else true 
          val externs = if false (*#removeExterns flags*)
                then List.filter removeUnusedExtern externs
                else externs
          in
            ST.tick cntPhases;
            B.MODULE{name=name, externs=externs, hlops=hlops, rewrites=rewrites, body=body}
          end

  end
