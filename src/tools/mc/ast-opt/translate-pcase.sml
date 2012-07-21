(* NOTE: *)
(* The way pcase is compiled, it causes a redundant match downstream. *)

(* translate-pcase.sml
 *
 * COPYRIGHT (c) 2007 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 *)

(* NOTE This translation is NOT RECURSIVE. *)
(*      It assumes the incoming expressions have been translated. *)

(* FIXME Put in cancellations where needed. *)

(* TODO Test exceptions. *)

(* TODO For 'a computations, should we make an 'a result future, rather than an 'a future? *)

structure TranslatePCase (* : sig

  (* An AST to AST translation of parallel cases. *)
    val tr : (AST.exp -> AST.exp) 
             -> AST.exp list * AST.pmatch list * AST.ty 
             -> AST.exp

  end *) = struct

  structure A = AST
  structure B = Basis
  structure F = Future1
  structure R = Rope

  structure D = DelayedBasis

  structure CB = CompletionBitstring
  type cbits = CB.t

(* maps from cbits to 'a *)
  structure CBM = RedBlackMapFn (struct
				   type ord_key = cbits
				   val compare = CB.compare
				 end)

  type matchmap = (A.match list) CBM.map (* maps of cbits to matches (case arms) *)

(* mkResPat : A.pat -> A.pat *)
(* Given a pattern (p : t), produce the pattern (RES(p) : t result). *)
  fun mkResPat pat = let
    val conRES = D.DataCon.resultRES ()
    val ty = TypeOf.pat pat
    in
      AST.ConPat (conRES, [ty], pat)
    end

(* mkExnPat : (AST.pat * AST.ty) -> AST.pat *)
(* Given a pattern p and type t, produce the pattern (Exn p : t result). *)  
  fun mkExnPat (pat, ty) = let
    val conEXN = D.DataCon.resultEXN ()
    in
      AST.ConPat (conEXN, [ty], pat)
    end

(* futureVars : A.exp list -> A.var list *)
  fun futureVars es = let
    fun go ([], _, acc) = List.rev acc
      | go (e::es, n, acc) = let
	  val ty = TypeOf.exp e
	  val name = "f" ^ Int.toString n
          val fV = Var.new (name, D.Ty.future ty)
	  in
	    go (es, n+1, fV::acc)
  	  end
    in
      go (es, 1, [])
    end

(* xformPPats : AST.ppat list -> AST.pat *)
(* A function to transform ppat lists to tuple pats for use in case exps. *)
(* ex: ? & 1 & (x, y) --> (_, Val 1, Val (x, y)) *)
  fun xformPPats ps = let
    fun xform (AST.NDWildPat ty) = AST.WildPat (D.Ty.result ty)
      | xform (AST.HandlePat (p, ty)) = mkExnPat (p, ty)
      | xform (AST.Pat p) = mkResPat p
    in
      AST.TuplePat (List.map xform ps)
    end

(* initMap : cbits list -> matchmap *)
(* Constructs a map whose keys are the distinct bitstrings in cbs, *)
(*   and all of whose values are the empty list. *)
(* (Those lists will later have matches consed onto them.) *)
  fun initMap (cbs : cbits list) : matchmap = let
    fun go ([], m) = m
      | go (c::cs, m) = 
	  if CBM.inDomain (m, c) then 
	    go (cs, m)
	  else 
	    go (cs, CBM.insert (m, c, []))
    in
      go (cbs, CBM.empty)
    end

(* cbOf : int -> A.pmatch -> cbits *)
(* Constructs a completion bits string from a pmatch: *)
(* - zeros for all ?s, ones for all others, or     *)
(* - all ones in the case of an otherwise branch.  *)  
(* Ths int argument says how many ones when an it's an otherwise. *)
  fun cbOf _ (A.PMatch (pps, _)) = CB.fromPPats pps
    | cbOf n (A.Otherwise _) = CB.allOnes n

(* mergeOne : given a map, a key (a cbits), and a pmatch, *)
(* construct a match and insert it into the map. *)
  fun mergeOne (t : A.ty) (m : matchmap, cb : cbits, pm : A.pmatch) 
      : matchmap = let
    val match = 
     (case pm
        of A.Otherwise (ts, e) => A.PatMatch (A.WildPat (D.Ty.result t), e)
	 | A.PMatch (ps, e) => A.PatMatch (xformPPats ps, e))
    val (m', ms) = CBM.remove (m, cb)
    val belongsLast = (case pm of A.Otherwise _ => true | _ => false)
    val ms' = if belongsLast then ms @ [match] else match :: ms
    in
      CBM.insert (m', cb, ms')
    end

(* merge : int -> AST.ty -> A.pmatch * matchmap -> matchmap *)
(* Merge the given pmatch into all appropriate slots in the map. *)
  fun merge (n : int) (t : A.ty) (pm : A.pmatch, m : matchmap) 
      : matchmap = let
    val cb = cbOf n pm
    fun go ([], m') = m'
      | go (cb' :: r, m') = let
          val m'' = if CB.sub (cb, cb') then mergeOne t (m', cb', pm) else m'
          in
	    go (r, m'')
          end
    in
      go (CBM.listKeys m, m)
    end

(* mkTy : AST.ty list -> cbits -> AST.ty *)
(* tup of results for types corres. to Ones -> pcaseResultTy *)
(* e.g., if ts is [int, bool, string] *)
(* and cb is 101 then this function yields *)
(* the type (int result * string result) *)
  fun mkTy ts cb = let
    fun go ([], [], tys) = AST.TupleTy (List.rev tys)
      | go (CB.Zero ::r1, _::r2, tys) = go (r1, r2, tys)
      | go (CB.One  ::r1, t::r2, tys) = go (r1, r2, D.Ty.result(t)::tys)
      | go _ = raise Fail
          "length of completion bitstring doesn't match # of exps in pcase"
    in
      go (cb, ts, [])
    end 

(* mkMatch : A.ty * A.ty list * cbits * A.var -> A.match * (A.var list) *)
(* mkMatch: construct a match with the right SOMEs, NONEs etc.  *)
(* ex: mkMatch (-, -, 1001, state1001) yields                  *)
(*       | (SOME t1, NONE, NONE, SOME t2) => state1001 (t1,t2) *)
  fun mkMatch (pcaseResultTy, eTys, cb, fV) = let
(*     val mkOptResTy = mkOptTy o mkResultTy *)
    fun varToExp v = A.VarExp (v, [])
    fun m ([], [], _, optPats, argVs) = let
          val tupPat = A.TuplePat (List.rev optPats)
	  val argVs' = List.rev argVs
          val fcall = A.ApplyExp (A.VarExp (fV, []), 
				  A.TupleExp (List.map varToExp argVs'),
				  pcaseResultTy)
          in
	    (A.PatMatch (tupPat, fcall), argVs')
          end
      | m (CB.Zero::bs, t::ts, n, optPats, argVs) = let
          val p = A.ConstPat (A.DConst (D.DataCon.optNONE (), [D.Ty.result t]))
          in
            m (bs, ts, n, p::optPats, argVs)
          end
      | m (CB.One::bs, t::ts, n, optPats, argVs) = let
          val varName = "t" ^ Int.toString n
	  val argV = Var.new ("t" ^ Int.toString n, D.Ty.result t)
	  val p = A.ConPat (D.DataCon.optSOME (), [D.Ty.result t], A.VarPat argV) 
          in
	    m (bs, ts, n+1, p::optPats, argV::argVs)
          end
      | m _ = raise Fail "ran out of types"
    in
      m (cb, eTys, 1, [], [])
    end

(* typeOfVar : A.var -> A.ty *)
  fun typeOfVar v = TypeOf.pat (A.VarPat v)

(* mkCancel : A.var -> A.exp *)
(* Given a variable (f) bound to some 'a future, return (cancel f). *)
  fun mkCancel (futV : A.var) : A.exp = let
    val inst = 
      (case typeOfVar futV
         of A.ConTy ([i], tyc) =>
             (if TyCon.same (tyc, F.futureTyc ()) then i
	      else raise Fail "not a future")
	  | _ => raise Fail "not a future")
    in
      A.ApplyExp (A.VarExp (D.Var.cancel1 (), [inst]),
		  A.VarExp (futV, []),
		  A.TupleTy [])
    end

(* mkPoll: Given a variable f bound to some 'a future, return (poll f).
 * ex: mkPoll (nf : int future) --> 
 *  ((poll : int future -> int result option) (nf : int future)) : int result option 
 *)
  fun mkPoll (futV : AST.var) : AST.exp = let
    val ty = typeOfVar futV
    val inst = 
     (case ty
        of A.ConTy ([i], tyc) => 
	    (if TyCon.same (tyc, F.futureTyc ()) 
	     then i
	     else raise Fail "not a future")
	 | _ => raise Fail "unexpected non-future type")
    in
      A.ApplyExp (A.VarExp (D.Var.poll (), [inst]),
		  A.VarExp (futV, []), (* FIXME Should this be the empty list? *)
		  D.Ty.option (D.Ty.result inst))
    end

(* patOf : A.match -> A.pat *) 
  fun patOf (A.PatMatch (p, _)) = p
    | patOf (A.CondMatch (p, _, _)) = p

(* isWild : A.pat -> bool *)
  fun isWild (A.WildPat _) = true
    | isWild _ = false

(* allWild : A.pat list -> bool *)
  val allWild = List.all isWild

(* patToString : A.pat -> string *)
(* This is only here to produce debugging messages. *)
  fun patToString p =
   (case p
      of A.ConPat (A.DCon {name, ...}, ts, innerP) => let
           val con = Atom.toString name
           in
	     concat [con, "[-]:", TypeUtil.toString (TypeOf.pat p)]
           end
       | A.TuplePat ps => 
	   concat ["(", String.concatWith "," (List.map patToString ps), ")"]
       | A.VarPat x => let
           val t = TypeOf.pat p
	   in
	     concat [Var.nameOf x, ":", TypeUtil.toString t]
	   end
       | A.WildPat t => concat ["_:", TypeUtil.toString t]
       | A.ConstPat k => "unexpected ConstPat"
      (* end case *))

(* matchWithPat : A.pat -> A.match -> A.match *)
(* A functional update of a match, such that its pattern is replaced. *)
  fun matchWithPat p m = 
   (case m
      of A.PatMatch (_, e) => A.PatMatch (p, e)
       | A.CondMatch (_, e1, e2) => A.CondMatch (p, e1, e2)
      (* end case *))

(* applyCB : cbits -> 'a list -> 'a list *)
(* Use the cbits to filter the 'a list. *)
(* ex: applyCB 01011 [p1,p2,p3,p4,p5] --> [p2,p4,p5] *)
  fun applyCB cb xs = let
    fun loop ([], [], acc) = List.rev acc
      | loop (b::bs, x::xs, acc) =
         (case b
            of CB.Zero => loop (bs, xs, acc)
	     | CB.One => loop (bs, xs, x::acc)
	    (* end case *))
      | loop _ = raise Fail "unequal lengths"
    in
      loop (cb, xs, [])
    end

(* seqPrepend : A.exp list -> A.exp -> A.exp       *)
(* Prepend all given expressions es onto e with ;. *)
(* ex: seqPrepend [e1,e2] e0 --> (e1; (e2; e0))    *)
  fun seqPrepend es e = List.foldr A.SeqExp e es

(* narrowMatch : cbits * A.var list * A.ty -> A.match -> A.match *)
  fun narrowMatch (cb, futVs, t) m = 
   (case patOf m
      of A.ConPat _ => raise Fail "BUG: unexpected ConPat"
       | A.VarPat _ => raise Fail "BUG: unexpected VarPat"
       | A.ConstPat _ => raise Fail "BUG: unexpected ConstPat"
       | A.WildPat _ => matchWithPat (A.WildPat t) m
       | A.TuplePat ps => let
	   val ps' = applyCB cb ps
	   val cancels = let
             (* cancel all futures that correspond to wildcards *)
	     fun loop ((A.WildPat _)::ps, f::fs, acc) = loop (ps, fs, f::acc)
	       | loop (p::ps, f::fs, acc) = loop (ps, fs, acc)
	       | loop ([], [], acc) = List.rev acc (* actually reversing isn't needed *)
	       | loop _ = raise Fail "unequal lengths"
	     val cancelThese = loop (ps, futVs, [])
	     in
               List.map mkCancel cancelThese
	     end
	   in
	     case m
	      of A.CondMatch _ => raise Fail "conditional matches unsupported for now"
	       | A.PatMatch (p, e) => let
		   val p' = A.TuplePat ps'
		   val e' = seqPrepend cancels e
		   in
		     A.PatMatch (p', e')
		   end
	   end	
      (* end case *))

(* narrowMatches : cbits * A.var list * A.ty -> A.match list -> A.match list *)
  fun narrowMatches (cb, futVs, t) = List.map (narrowMatch (cb, futVs, t))

(* mkLam : A.ty * A.var * A.var list * cbits * match list * A.var list -> A.lambda *)
(* This function is called to finish off the translation in tr below. *)
(* FIXME This should also cancel the ongoing, no-longer-needed futures. *)
  fun mkLam (pcaseResultTy, fNameV, vars, cb, caseArms, futVs) = let
    val vTys = List.map typeOfVar vars
    val t = A.TupleTy vTys
    val argV = Var.new ("x", t)
    val caseArms' = narrowMatches (cb, futVs, t) caseArms
    val body = A.CaseExp (A.VarExp (argV, []), caseArms', pcaseResultTy)
    in
      A.FB (fNameV, argV, body)
    end

(* mkStateMachine : AST.exp list * matchmap * AST.ty -> AST.exp *)
(* A function to build a batch of functions implementing a state machine *)
(* Given a map of completion bitstrings, produce lists of matches. *)
  fun mkStateMachine (es: A.exp list,
		      m: matchmap,
		      pcaseResTy: AST.ty) : AST.exp = let
    val expTys = List.map TypeOf.exp es
    val kmss = CBM.listItemsi m
    val goV = Var.new ("go", A.FunTy (Basis.unitTy, pcaseResTy))
    val applyGo = A.ApplyExp (A.VarExp (goV, []), A.TupleExp [], pcaseResTy)
    val default = A.WildPat (A.TupleTy (map (D.Ty.option o D.Ty.result) expTys))
    val defaultMatch = A.PatMatch (default, applyGo)
    val u = Var.new ("u", Basis.unitTy)
    val fVs = futureVars es
    fun mkGo matches = let
      val pollTuple = A.TupleExp (map mkPoll fVs)
      val body = A.CaseExp (pollTuple, matches @ [defaultMatch], pcaseResTy)
      val arg = Var.new ("u", Basis.unitTy) 
      in
	A.FB (goV, arg, body)
      end
    fun isAllOnes cb = CB.eq (cb, CB.allOnes (CB.length cb))
    fun b ([], matches, lams, fnames) = mkGo matches :: lams
      | b ((cb,ms)::t, matches, lams, fnames) = let
          val name = "state" ^ CB.toString cb
	  val ty = A.FunTy (mkTy expTys cb, pcaseResTy)
	  val nameV = Var.new (name, ty)
	  val (m, vs) = mkMatch (pcaseResTy, expTys, cb, nameV)
(* FIXME What about the order of the matches? *)
	  val ms' = if isAllOnes cb then ms else (ms @ [defaultMatch])
	  val f = mkLam (pcaseResTy, nameV, vs, cb, ms', fVs)
          in
	    b (t, m::matches, f::lams, name::fnames)
          end
    val lams = b (kmss, [], [], []) 
    val knot = A.FunBind lams           
    fun bind (v, e, e') = A.LetExp (A.ValBind (A.VarPat v, F.mkFuture e), e')
    in
      ListPair.foldrEq bind (A.LetExp (knot, applyGo)) (fVs, es)
    end

(* Construct an "otherwise => raise Match" branch of the given type. *)
  fun otherwiseRaiseMatch (t: A.ty) : A.pmatch = let
    val exnMatch = A.ConstExp (A.DConst (Basis.exnMatch, []))
    val _ = raise Fail "FIXME"
    val ts = raise Fail "FIXME"
    in
      A.Otherwise (ts, A.RaiseExp (Error.UNKNOWN, exnMatch, t)) 
    end

(* The function "otherwise" appends "otherwise => raise Match" if no Otherwise is present. *)
  fun otherwise (pms: A.pmatch list, ty: A.ty) : A.pmatch list = let
  (* count the number of otherwise branches *)
    val n = List.foldl (fn (A.Otherwise _, tot) => tot+1 | (_, tot) => tot) 0 pms
  (* FIXME raise this error the right way (via Err) *)
    val _ = if n>1 then raise Fail("too many otherwise branches in pcase") (* parser bug? *) else ()
    in
      if n = 0 then pms @ [otherwiseRaiseMatch ty] else pms
    end

(* A pcase looks like this:
 * PCaseExp of (exp list * pmatch list * ty) (ty is result type ) 
 *)   	   
  fun tr (trExp: A.exp -> A.exp)
         (es: A.exp list, pms: A.pmatch list, pcaseResTy: A.ty) : A.exp = let
    val pms' = otherwise (pms, pcaseResTy)
  (* buildMap : A.pmatch list -> A.matchmap *)
  (* build map : collect bitstrings, then merge branches in *)
    fun buildMap pms = let
      val nExps  = List.length es
      val expTys = map TypeOf.exp es
      val cbs    = map (cbOf nExps) pms
      in
        List.foldl (merge nExps (AST.TupleTy expTys)) (initMap cbs) pms
      end
    val m = buildMap pms'
    in
      mkStateMachine (es, m, pcaseResTy)
    end

(* --- some tests follow --- *)

(*
  structure T = TestUtils

  val zero = T.int 0
  val one  = T.int 1

  fun t (A.PCaseExp (es, pms, ty)) = tr (fn e => e) (es, pms, ty)
    | t _ = raise Fail "expecting a pcase"

  val c0 = A.PCaseExp ([zero],
		       [A.Otherwise one],
		       Basis.intTy)

  val c1 = A.PCaseExp ([zero, zero],
		       [A.PMatch ([T.intPPat 1, A.NDWildPat Basis.intTy], zero),
 		        A.Otherwise one],
		       Basis.intTy)

  val c2 = let
    val n = Var.new ("n", Basis.intTy)
    val m = Var.new ("m", Basis.intTy)
    in
      A.PCaseExp ([A.VarExp (n, []), A.VarExp (m, [])],
		  [A.PMatch ([T.intPPat 1, A.NDWildPat Basis.intTy], zero),
		   A.PMatch ([A.NDWildPat Basis.intTy, T.intPPat 2], zero),
		   A.Otherwise one],
		  Basis.intTy)
    end

(*  link time error:
  val c3 = A.PCaseExp ([zero],
		       [A.Otherwise (t c0)],
		       Basis.intTy)
*)
  fun mkTest pcase = (PrintAST.printExpNoTypes pcase;
		      PrintAST.printComment "-->";
		      PrintAST.printExpNoTypes (t pcase))

  fun test 0 = mkTest c0
    | test 1 = mkTest c1
    | test 2 = mkTest c2
(*  | test 3 = mkTest c3 *)
    | test _ = print "No such test.\n"
*)

end
    

