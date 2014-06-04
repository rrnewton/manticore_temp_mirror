(* arity-raising.sml
 *
 * COPYRIGHT (c) 2008 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 *
 * This transformation combines useless variable elimination with argument
 * flattening (or arity-raising).
 *)

functor ArityRaisingFn (Spec : TARGET_SPEC) : sig

    val transform : CPS.module -> CPS.module

  end = struct

    structure PPt = ProgPt
    structure C = CPS
    structure CV = C.Var
    structure VSet = CV.Set
    structure U = CPSUtil
    structure CTy = CPSTy
    structure CFA = CFACPS
    structure ST = Stats
    structure Census = CPSCensus

  (***** controls ******)
    val enableArityRaising = ref false 
    val argumentOnly = ref false
    val arityRaisingDebug = ref false
    val multiPass = ref true
    val maxParams = ref Spec.availRegs
    val dumpArityRaising = ref false

    val () = List.app (fn ctl => ControlRegistry.register CPSOptControls.registry {
              ctl = Controls.stringControl ControlUtil.Cvt.bool ctl,
              envName = NONE
            }) [
              Controls.control {
                  ctl = enableArityRaising,
                  name = "arity-raising",
                  pri = [0, 1],
                  obscurity = 0,
                  help = "enable arity raising"
                },
              Controls.control {
                  ctl = arityRaisingDebug,
                  name = "arity-raising-debug",
                  pri = [0, 1],
                  obscurity = 0,
                  help = "debug arity raising"
                  },
              Controls.control {
                  ctl = argumentOnly,
                  name = "argument-only",
                  pri = [0, 1],
                  obscurity = 0,
                  help = "use argument-only arity raising"
                  },
              Controls.control {
                  ctl = multiPass,
                  name = "multipass",
                  pri = [0, 1],
                  obscurity = 0,
                  help = "use multipass signature changes"
                  },
              Controls.control {
                  ctl = dumpArityRaising,
                  name = "dump-arity-raising",
                  pri = [0, 1],
                  obscurity = 0,
                  help = "output the result of arity raising to a file"
                  }
             ]
             
    val _ = ControlRegistry.register CPSOptControls.registry {
            ctl = Controls.stringControl ControlUtil.Cvt.int (                      
              Controls.control {
                  ctl = maxParams,
                  name = "max-arity-params",
                  pri = [0, 1],
                  obscurity = 0,
                  help = "limit on the maxiumum total parameters arity raising will increase up to"
                  }),
            envName = NONE }
            
  (***** Statistics *****)
    val cntCandidateFun		= ST.newCounter "cps-arity:candidate-fn"
    val cntFlattenedFun		= ST.newCounter "cps-arity:flattened-fn"
    val cntSelElim		= ST.newCounter "cps-arity:select-elim"
    val cntAllocElim		= ST.newCounter "cps-arity:alloc-elim"
    val cntAllocIntro		= ST.newCounter "cps-arity:alloc-intro"

    val cntEscapingFuns         = ST.newCounter "cps-arity:escaping-funs"
    val cntUselessElim          = ST.newCounter "cps-arity:useless-elim"
    val cntUselessScanPasses    = ST.newCounter "cps-arity:useless-scan-passes"
    val cntFunsToConts          = ST.newCounter "cps-arity:funs-to-conts"

    val cntUnusedStmt           = ST.newCounter "cps-arity:unused-stmt"
    val cntUnusedParam          = ST.newCounter "cps-arity:unused-param"
    val cntUnusedArg            = ST.newCounter "cps-arity:unused-arg"
    val cntCleanupPasses        = ST.newCounter "cps-arity:cleanup-passes"
    val cntSignaturePasses      = ST.newCounter "cps-arity:signature-passes"

  (***** Analysis *****)

  (* access paths for variables that are derived from function parameters *)
    datatype path
      = PARAM of int		(* ith function parameter *)
      | SEL of int * path	(* selection from parameter *)

  (* a reversed path is the parameter index paired with a list of the selectors *)
    type rev_path = (int * int list)

    fun pathToString p = let
	  fun toStringList (PARAM i) = [Int.toString i, "@"]
	    | toStringList (SEL(i, p)) = Int.toString i :: "." :: toStringList p
	  in
	    concat(rev(toStringList p))
	  end

  (* reverse a path to a list of integers.  The parameter index will be the first item
   * in the resulting list.
   *)
    fun pathToList p = let
	  fun toList (PARAM i, l) = (i, l)
	    | toList (SEL(i, q), l) = toList(q, i::l)
	  in
	    toList (p, [])
	  end

  (* construct a path from a reversed representation. *)
    fun listToPath (i, l) = let
	  fun toPath ([], p) = p
	    | toPath (j::l, p) = toPath(l, SEL(j, p))
	  in
	    toPath (l, PARAM i)
	  end

    datatype path_order = PathLess | PathPrefix | PathEq | PathGreater

  (* compare two reversed paths *)
    fun compareRevPath (p, q) = let
	  fun cmp ([], []) = PathEq
	    | cmp ([], _) = PathPrefix
	    | cmp (_, []) = PathGreater
	    | cmp (i::r, j::r') = (case Int.compare(i, j)
		 of LESS => PathLess
		  | EQUAL => cmp(r, r')
		  | GREATER => PathGreater
		(* end case *))
	  in
	    cmp ((op ::)p, (op ::)q)
	  end

  (* is a reversed path a prefix of another? *)
    fun isPrefix ((i, p) : rev_path, (j, q)) = if (i = j)
	  then let
	    fun isPrefix' ([], p) = true
	      | isPrefix' (_, []) = false
	      | isPrefix' ((i : int)::r, j::r') = (i = j) andalso isPrefix'(r, r')
	    in
	      isPrefix' (p, q)
	    end
	  else false

  (* path equality *)
    fun samePath (PARAM i, PARAM j) = (i = j)
      | samePath (SEL(i, p), SEL(j, q)) = (i = j) andalso samePath(p, q)
      | samePath _ = false

  (* a lexical ordering that treats the path root as most significant *)
    fun comparePath (p, q) = let
	  val (i, p) = pathToList p
	  val (j, q) = pathToList q
	  in
	    case Int.compare(i, j)
	     of EQUAL => List.collate Int.compare (p, q)
	      | order => order
	    (* end case *)
	  end

  (* is path p derived from q? *)
    fun isDerivedFrom (p, q) = isPrefix (pathToList p, pathToList q)
	  
    structure PMap = RedBlackMapFn (
      struct
	type ord_key = path
	val compare = comparePath
      end)

    fun lookupPath (pmap, p) = (case PMap.find(pmap, p)
	   of NONE => raise Fail(concat["lookupPath(-, ", pathToString p, ")"])
	    | SOME cnt => cnt
	  (* end case *))

  (* The signature of a function f is a list of reversed paths (i.e., int lists) that represent
   * the function's flattened arguments.  It has the following properties:
   *  1) no path is derived from another in the list,
   *  2) the use counts of the paths are > 0
   *  3) for any path p in dom(pmap) with pmap(p) > 0, either p
   *     is in the list or is derived from a path in the list.
   *)
    type fun_sig = rev_path list

    fun sigToString sign = let
	  fun f [] = [")"]
	    | f [s] = [pathToString(listToPath s), ")"]
	    | f (s::r) = pathToString(listToPath s) :: ", " :: f r
	  in
	    String.concat ("(" :: f sign)
	  end

  (* compute a maximal signature of a candidate function from its pmap.  The maximal signature
   * includes any path that has a non-zero count.
   *)
    fun computeMaxSig pmap =
	  PMap.foldri (fn (p, ref 0, l) => l | (p, _, l) => (pathToList p)::l) [] pmap

  (* Compute the signature of a candidate function from its pmap. *)
    fun computeSig pmap = let
	(* filter out paths that are derived from others on the list; for this
	 * process, we rely on the ordering used to structure the pmap.
         *
         * Additionally, this function is where we limit the maxiumum number
         * of parameters for the signature based on the control.
	 *)
	  fun filter ([], _, l) = List.rev l
	    | filter (p::r, q, l) = if isPrefix(q, p)
		then filter (r, q, l)
		else filter (r, p, p::l)
          val filteredSig = filter (computeMaxSig pmap, (~1, []), [])
          fun merge ((i,p1)::ps) = let
              val justParam = (i,[])
          in
              if List.exists (fn p => isPrefix(justParam, p)) ps
              then justParam::(filter (ps, justParam, []))
              else (i,p1)::merge(ps)
          end
            (* If we couldn't merge any more, give up *)
            | merge ls = ls 
          fun collapse (0, l) = l
            | collapse (i, xs) = collapse (i-1, merge(xs))
          fun clamp (l) = let
              val over = List.length l - !maxParams
          in
              if (over <= 0)
              then l
              else collapse (over, l)
          end
    in
        clamp filteredSig	
    end

  (* merge two signatures to have a common calling convention.
   * We use this operation to handle the case where there are multiple
   * possible functions that can be called at a single call site.
   * If we trivially flattened, we could end up with different parameter
   * conventions and incompatible calls. This unifies the convention
   * across the two functions.
   *)
    fun sigMeet (sig1, sig1Type, sig2) = let
	  fun removeDerivedPaths (p, q::qs) = if isPrefix(p, q)
		then removeDerivedPaths (p, qs)
		else q::qs
	    | removeDerivedPaths (_, []) = []
          val defaultArgPath = (0,[])
          val params = case sig1Type
                        of CPSTy.T_Fun(params, _) => params
                         | CPSTy.T_Cont(params) => params
                         | _ => raise Fail (concat["non-function type passed to sigMeet: ", CPSTyUtil.toString sig1Type])
          (* We only check against the signature being merged into. This
           * is because we'll use the result of our signature creation process
           * and feed it through sigMeet a second time to make sure it's compatible
           * with all of the predecessors.
           *)

          fun safeSelection (i, l) = if i >= List.length params
                                     then defaultArgPath
                                     else (i, safeSelectionHelper (l, List.nth (params, i)))
          and safeSelectionHelper (x::xs, CTy.T_Tuple (_, tys)) =
              if (x < List.length tys)
              then x::(safeSelectionHelper (xs, List.nth (tys, x)))
              else []
            | safeSelectionHelper (_, _) = []
              
	  fun f (p::ps, q::qs, mergedSig) = (case compareRevPath(p, q)
		 of PathLess => f(ps, q::qs, (safeSelection p)::mergedSig)
		  | PathPrefix => f (ps, removeDerivedPaths (p, qs), p::mergedSig)
		  | PathEq => f (ps, qs, p::mergedSig)
		  | PathGreater => if isPrefix (q, p)
		      then f (removeDerivedPaths (q, ps), qs, q::mergedSig)
		      else f (p::ps, qs, (safeSelection q)::mergedSig)
		(* end case *))
            | f ([], [], mergedSig) = mergedSig
	    | f (ps, [], mergedSig) = if compareRevPath (defaultArgPath, hd ps) = PathEq
                                      then (hd ps)::mergedSig
                                      else List.revAppend(ps, mergedSig)
	    | f ([], q::qs, mergedSig) = if compareRevPath (defaultArgPath, q) = PathEq
                                      then q::mergedSig
                                      else f([], qs, (safeSelection q)::mergedSig)
	  in
	    List.rev (f (sig1, sig2, []))
	  end

    datatype call_site = SITE of {
	    enclFn : C.var option,	(* enclosing function of call site; NONE if it is not *)
					(* a candidate. *)
	    ppt : ProgPt.ppt,		(* program-point of call site *)
	    callees : C.var list,	(* the candidate functions that f can be bound to *)
	    f : C.var,			(* variable bound to the function at the call site *)
	    args : C.var list		(* arguments to call *)
	  }

    fun siteToString (SITE{enclFn, f, args, ...}) = concat[
	    CV.toString f, " (", String.concatWith ", " (List.map CV.toString args),
	    case enclFn of NONE => ")" | SOME g => concat[") in ", CV.toString g]
	  ]


  (* a derived parameter is either a local variable in the function or a potential
   * argument to some call that whose arguments will be flattened.
   *)
    datatype derived_param
      = VAR of C.var			(* a local variable derived from a formal parameter *)
      | ARG of call_site * path		(* an argument to a candidate function *)

    fun paramToString (VAR x) = CV.toString x
      | paramToString (ARG(SITE{args, ...}, path)) = let
	  val (i, l) = pathToList path
	  in
	    concat(
	      CV.toString(List.nth(args, i)) ::
		List.foldr (fn (j, l) => "."::Int.toString j::l) [] l)
	  end

  (* a finite map keyed by derived parameters *)
    structure ParamMap = RedBlackMapFn (
      struct
	type ord_key = derived_param
	fun compare (VAR x, VAR y) = CV.compare(x, y)
	  | compare (VAR _, ARG _) = LESS
	  | compare (ARG _, VAR _) = GREATER
	  | compare (ARG(SITE{ppt=ppt1, ...}, path1), ARG(SITE{ppt=ppt2, ...}, path2)) = (
	      case ProgPt.compare(ppt1, ppt2)
	       of EQUAL => comparePath (path1, path2)
		| order => order
	      (* end case *))
      end)

    (* Compute param list from the final signature,
     * vmap of the VAR->PATH mappings, and original params
     * If a variable doesn't exist in the parammap for the input
     * sign, then it's a parameter that was added for signature-matching
     * with other functions that share call sites and will be unused
     * in the function.
     *)
    fun computeParamList (origParams, vmap, sign) = let
        fun computeParam paramPath = 
            case paramPath
             of (i, []) => List.nth (origParams, i)
              | (i, l) => let
                    val path = listToPath (i, l)
                    val vmap' = ParamMap.filter (fn (p) => comparePath (p,path) = EQUAL) vmap
                in
                    case ParamMap.firsti vmap'
                     of SOME(VAR(x), _) => x
                      | _ => let
                            val baseParam = List.nth (origParams, i)
                            fun findSubtype (i::l, CTy.T_Tuple (_, tys)) =
                                findSubtype (l, List.nth (tys, i))
                              | findSubtype (i::l, ty) = raise Fail (concat["Signature contains invalid path selecting from type ",
                                                                            CPSTyUtil.toString ty])
                              | findSubtype (_, ty) = ty
                            val paramType = findSubtype (l, CV.typeOf baseParam)
                        in
                            CV.new ("unused", paramType)
                        end
                end
    in
        List.map computeParam sign
    end

  (* property for tracking the call sites of candidate functions; we also use this
   * property to distinguish candidate functions from non-candidate functions.
   *)
    local
      val {clrFn, setFn, peekFn, ...} = CV.newProp (fn f => ref([] : call_site list))
    in
  (* get the list of call sites of a function; [] for non-candidates *)
    fun getSites f = (case peekFn f
	   of NONE => []
	    | SOME l => !l
	  (* end case *))

  (* if a bound variable is a candidate function, then mark it
   * by initializing its call-site list
   *
   * A function f is a candidate for flattening if it satisfies the following
   * properties:
   *
   *	1) f's argument type is a non-mutable tuple
   *    2) f does not escape, so we can replace all copies of it
   *	3) and either
   *	      a) f has lexically known application sites
   *	      b) f has a member of a set of known functions with known call sites
   *)
    fun markCandidate f = let
	  fun mark () =
		if (not(CFA.isEscaping f))
                   andalso ((CV.appCntOf f > 0)
		            orelse (case CFA.equivalentFuns f of [] => false | _ => true))
		then (case CV.typeOf f
		     of CTy.T_Fun(tys, _) =>
			if List.exists (fn CTy.T_Tuple(false, _) => true | _ => false) tys
			then (
                            ST.tick cntCandidateFun;
			    setFn (f, ref []))
			else ()
		     | CTy.T_Cont(tys) =>
			if List.exists (fn CTy.T_Tuple(false, _) => true | _ => false) tys
			then (
                            ST.tick cntCandidateFun;
			    setFn (f, ref []))
			else ()
		      | _ => ()
		     (* end case *))
		else () 
	  in
	    case CV.kindOf f
	     of C.VK_Fun _ => mark ()
	      | C.VK_Cont _ => mark ()
	      | _ => ()
	    (* end case *)
	  end
    
    (* is a function a candidate? *)
    fun isCandidate f = Option.isSome(peekFn f)

  (* add an application site to any candidate functions that are called from
   * the site.
   *)
    fun addCallSite (enclFn, ppt, f, args) = (case CFA.valueOf f
	   of CFA.LAMBDAS gs => let
		val callees = VSet.listItems gs
		val site = SITE{enclFn = enclFn, ppt = ppt, callees = callees, f = f, args = args}
		fun add g = (case (peekFn g)
		       of NONE => ()
			| SOME l => (l := site :: !l)
		      (* end case *))
		in
		  List.app add callees
		end
	    | _ => ()
	  (* end case *))
    end (* local *)

  (* Candidate info property *)
    type info = {
	  vmap : path ParamMap.map,
	  pmap : int ref PMap.map,
	  sign : fun_sig,
          params : C.var list,
          rets : C.var list,
          newParams : C.var list option,
          newRets : C.var list option
	}
    local
      val {clrFn, getFn : CV.var -> info, setFn, ...} =
	    CV.newProp (fn x => raise Fail ((CV.toString x) ^ " is not a candidate"))
    in
    val clearInfo = clrFn
    val getInfo = getFn
    fun setInfo (f, vmap, pmap, params, rets, sign, newParams, newRets) =
	  setFn (f, {vmap=vmap, pmap=pmap, sign=sign, params=params, rets=rets,
                newParams=newParams, newRets=newRets});
    end

(* +DEBUG *)
    fun printCandidate f = let
	  val {vmap, pmap, sign, params, ...} = getInfo f
	  in
	    print(concat["candidate ", CV.toString f, " : ", sigToString sign, "\n"]);
	    print "  vmap:\n";
	    ParamMap.appi
	      (fn (x, p) => print(concat[
		  "    ", paramToString x, " --> ", pathToString p, ", cnt = ",
		  Int.toString(!(valOf(PMap.find(pmap, p)))), "\n"
		])) vmap;
	    print "  call sites:\n";
	    List.app (fn site => print(concat["    ", siteToString site, "\n"])) (getSites f);
            print " new param names:";
            List.app (fn v => print (CV.toString v ^ " ")) (computeParamList (params, vmap, sign)); print "\n"
	  end
(* -DEBUG *)

    fun addToRef (r, n) = r := !r + n

  (* property for tracking bindings to function bodies, used in useful
   * variable analysis
   *)
    local
      val {setFn, getFn, peekFn, ...} = CV.newProp (fn f => NONE : C.lambda option)
    in
    fun setFB (f,b) = setFn (f, SOME(b))
    fun getFB f = getFn f
    end

    (* property mapping from a variable to its defining function. This is used
     * during the flattening pass over the captured variables of a function to
     * see if there is a lexically equivalent shorter name for the same
     * access path.
     *)
    local
        val {setFn, getFn, ...} = CV.newProp (fn f => (NONE : C.var option))
    in
    fun setParent (f,p) = setFn (f, SOME(p))
    fun getParent f = getFn f
    end

    val escaping = ref ([] : C.var list)

  (* the first part of the analysis is to gather all of the candidate functions and
   * their call sites.  We also compute the initial vmaps and pmaps based on the selects
   * in the candidate-function bodies.  vmap maps variables to selection paths and pmap maps
   * selection paths to use counts.
   *)
    fun gather (module as C.MODULE{body, ...}) : C.var list = let
	(* list of candidate functions *)
	  val candidates = ref []
	(* analyse a bound function or continuation *)
	  fun analyseLambdas fbs = let
	      fun analyseFB (fb as C.FB{f, body, ...}) = (
                  setFB(f,fb) ;
                  if CFACPS.isEscaping f
                  then (ST.tick cntEscapingFuns;
                        escaping := f :: !escaping)
                  else () ;
                  if isCandidate f
		  then analyseCandidate fb
		  else walkExp body)
	      in
		List.app analyseFB fbs
	      end
	(* analyse the body of a candidate *)
	  and analyseCandidate (C.FB{f, params, rets, body, ...}) = let
	      (* construct an initial mapping from the parameters to their paths
	       * and from their paths to their use counts.
	       *)
		val (vmap, pmap) = let
		      fun f (_, [], vm, pm) = (vm, pm)
			| f (i, x::r, vm, pm) = let
			    val p = PARAM i
			    val vm = ParamMap.insert(vm, VAR x, p)
			    val pm = PMap.insert(pm, p, ref(CV.useCount x))
			    in
			      f (i+1, r, vm, pm)
			    end
		      in
			f (0, params, ParamMap.empty, PMap.empty)
		      end
                val _ = List.app (fn p => setParent (p, f)) params

                fun isUnsafe (unsafe::rest, p) =
                    if isDerivedFrom (p, unsafe)
                    then true
                    else isUnsafe (rest, p)
                  | isUnsafe ([], _) = false
	      (* analyse the body of the candidate function *)
		fun doExp (vmap, pmap, C.Exp(ppt, t), unsafeParams) = (case t
		       of (C.Let([x], C.Select(i, y), e)) => (
                            setParent (x, f) ;
			    case ParamMap.find(vmap, VAR y)
			     of NONE => doExp(vmap, pmap, e, unsafeParams)
			      | SOME p => (
                                case (!argumentOnly, (length (#2(pathToList p))) > 0)
                                 of (true, true) => doExp(vmap, pmap, e, unsafeParams)
                                  | (_, _) => (
                                    let
				        val q = SEL(i, p)
				        val vmap' = ParamMap.insert(vmap, VAR x, q)
				        (* decrement p's count *)
				        val cnt = lookupPath(pmap, p)
				        val _ = addToRef (cnt, ~1)
				        (* either add q to the path map or update its count *)
				        val (vmap, pmap) = (
                                            case PMap.find(pmap, q)
					     of NONE => (
                                                if isUnsafe (unsafeParams, p)
                                                then (addToRef (cnt, 1) ; (vmap, pmap))
                                                else (vmap', PMap.insert(pmap, q, ref(CV.useCount x))))
					      | SOME cnt => (addToRef(cnt, CV.useCount x);
                                                             (vmap', pmap))
					(* end case *))
				    in
				        doExp (vmap, pmap, e, unsafeParams)
				    end)))
			| (C.Let(_, _, e)) => doExp (vmap, pmap, e, unsafeParams)
			| (C.Fun(fbs, e)) => (
			    analyseLambdas fbs;
			    doExp (vmap, pmap, e, unsafeParams))
			| (C.Cont(fb, e)) => (
			    analyseLambdas [fb];
			    doExp (vmap, pmap, e, unsafeParams))
			| (C.If(x, e1, e2)) => let
                            val condVars = CondUtil.varsOf x
                            val unsafeParams = foldl (fn (x,unsafeParams) =>
                                                         (case ParamMap.find(vmap, VAR x)
                                                           of NONE => unsafeParams
                                                            | SOME p => p::unsafeParams))
                                               unsafeParams condVars
			    val (vmap, pmap) = doExp (vmap, pmap, e1, unsafeParams)
			    val (vmap, pmap) = doExp (vmap, pmap, e2, unsafeParams)
			    in
                              (vmap, pmap)
			    end
			| (C.Switch(x, cases, dflt)) => let
                              (* Switch is used for datatype dispatch. Therefore, add
                               * not only the variable being used but also the parent of
                               * the path, as very often that variable represents the type
                               * tag of a datatype.
                               *)
                            val unsafeParams = (
                                case ParamMap.find(vmap, VAR x)
                                 of NONE => unsafeParams
                                  | SOME p => (
                                    case p
                                     of SEL(_, p') => p::(p'::unsafeParams)
                                      | PARAM(_) => p::unsafeParams
                                    (* end case *))
                            (* end case *))
			    val (vmap, pmap) = (case dflt
				   of SOME e => doExp(vmap, pmap, e, unsafeParams)
				    | NONE => (vmap, pmap)
				  (* end case *))
			    fun doCase ((_, e), (vmap, pmap)) = doExp(vmap, pmap, e, unsafeParams)
			    in
			      List.foldl doCase (vmap, pmap) cases
			    end
			| (C.Apply(g, args, _)) => (
			    addCallSite (SOME f, ppt, g, args);
			    (vmap, pmap))
			| (C.Throw(k, args)) => (
			    addCallSite (SOME f, ppt, k, args);
			    (vmap, pmap))
		      (* end case *))
		val (vmap, pmap) = doExp(vmap, pmap, body, [])
	      (* the "argument shape" of f is a list of paths such that
	       *  1) no path is derived from another in the list,
	       *  2) the use counts of the paths are > 0
	       *  3) for any path p in dom(pmap) with pmap(p) > 0, either p
	       *     is in the list or is derived from a path in the list.
	       *)
		in
		  ST.tick cntCandidateFun;
		  setInfo (f, vmap, pmap, params, rets, [(0,[])], NONE, NONE);
		  candidates := f :: !candidates
		end (* analyseCandidate *)
	(* walk an expression looking for candidates *)
	  and walkExp (C.Exp(ppt, t)) = (case t
		 of (C.Let(_, _, e)) => walkExp e
		  | (C.Fun(fbs, e)) => (
		      analyseLambdas fbs;
		      walkExp e)
		  | (C.Cont(fb, e)) => (
		      analyseLambdas [fb];
		      walkExp e)
		  | (C.If(x, e1, e2)) => (walkExp e1; walkExp e2)
		  | (C.Switch(x, cases, dflt)) => (
		      List.app (walkExp o #2) cases;
		      Option.app walkExp dflt)
		  | (C.Apply(g, args, _)) => addCallSite (NONE, ppt, g, args)
		  | (C.Throw(k, args)) => addCallSite (NONE, ppt, k, args)
		(* end case *))
	  in
	  (* first we mark the candidate functions.  This uses setFn to create an entry mapping
             the variable to an empty reference of call sites, which later gets filled in.*)
	    U.applyToBoundVars markCandidate module;
	  (* first analyse the module to determine the candidate functions, their
	   * call sites, and their parameter access patterns.
	   *)
	    analyseLambdas [body];
	    !candidates
	  end

  (* Attempt to come up with a combined signature via sigMeet. Note
   * that non-candidate calls cancel out any attempt to further simplify
   * the signature.
   * After we come up with a proposed signature, we pass back through to get the
   * final version that works with valid selection paths from all of the shared functions.
   * To ensure compatible representations, we pass over all of the functions, pulling out
   * type associated with each parameter and ensuring it works.
   *)
    fun computeFunSig (f) = let
        val {pmap,...} = getInfo f
    in
        computeSig pmap
    end
    fun sigOfFuns [] = raise Fail "no functions"
      | sigOfFuns [f] = computeFunSig f
      | sigOfFuns (l as f::r) = let
            val canMeet = List.foldl (fn (g, b) => if (b) then (isCandidate g) else b) true l
        in
            if (canMeet) then let
                    fun meetSigs (g, sign) =
                        sigMeet(computeFunSig g, CV.typeOf g, sign)
                    val proposed = List.foldl meetSigs
                                              (computeFunSig f) r
                    val final = List.foldl meetSigs proposed l
                    fun getTypes (f) = let
                        val {params, vmap, ...} = getInfo f
                        val paramList = computeParamList (params, vmap, final)
                    in
                        List.map CV.typeOf paramList
                    end
                    fun compatibleTypings ([], []) = true
                      | compatibleTypings (ty1::tys1, ty2::tys2) =
                        CPSTyUtil.match (ty1, ty2) andalso compatibleTypings (tys1, tys2)
                      | compatibleTypings (_, _) = raise Fail "Type lists of different lengths."
                    fun checkAll (ty1, ty2::tys2) = compatibleTypings (ty1, ty2) andalso checkAll (ty2, tys2)
                      | checkAll (ty1, []) = true
                in
                    if checkAll ((getTypes f), (List.map getTypes r))
                    then final
                    else [(0, [])]
                end
            else
                [(0, [])]
        end

    val signaturesChanged = ref false
    fun computeValidSignatures (candidateSet) = let
        val candidateList = VSet.listItems candidateSet
        val _ = if !arityRaisingDebug
                then print (concat["Merging signatures for: ",
                                   concat(List.foldr (fn (a, rr) => (CV.toString a)::" "::rr)
                                                     [] candidateList),
                                   "\n"])
                else ()
        val sharedSig = sigOfFuns candidateList
        val changed = List.exists (fn (v) => if isCandidate v
                                             then let
                                                     val {sign as origSign, ...} = getInfo v
                                                 in
                                                     not(length origSign = length sharedSig) orelse
                                                     not(ListPair.all (fn (s1,s2) => compareRevPath(s1, s2)=PathEq) (origSign, sharedSig))
                                                 end
                                             else false) candidateList
        val _ = if changed
                then (signaturesChanged := true)
                else ()
        fun setNewSignature (candidate) =
            if isCandidate candidate
            then let
                    val {vmap, pmap, params, rets, sign, newParams, newRets} = getInfo candidate
                in
                    if !arityRaisingDebug
                    then print (concat[CV.toString candidate, " ORIG: ",
                                       sigToString sign, " NEW: ",
                                       sigToString sharedSig, "\n"])
                    else ();
                    setInfo (candidate, vmap, pmap, params, rets, sharedSig, newParams, newRets)
                end
            else ()
    in
        if changed
        then let
                fun collectSites (cand, sites) = let
                    fun maybeAddSite (site as SITE{ppt,...}, sites) =
                        if List.exists (fn (_, SITE{ppt=ppt',...}) => ProgPt.same(ppt',ppt)) sites
                        then sites
                        else (cand,site)::sites
                in
                    List.foldr maybeAddSite sites (getSites cand)
                end
                val sites = List.foldr collectSites [] candidateList
                fun updateCallSite (cand, site as SITE{enclFn=SOME(enclFn), args,...}) = let
                    val {sign=callSign,...} = getInfo cand
		    val {vmap, pmap, params, rets, sign, newParams, newRets} = getInfo enclFn
                    fun decrementUsage (i : int, sels : int list) = let
                        val arg = List.nth (args, i)
                    in
                        case ParamMap.find(vmap, VAR arg)
                         of NONE => ()
                          | SOME p => let
                                val (p',l') = pathToList p
                                val q = listToPath (p', l'@sels)
                            in
                                case PMap.find (pmap, q)
                                 of NONE => ()
                                  | SOME(cnt) => (addToRef (cnt, ~1))
                            end
                    end
                    val _ = List.app decrementUsage callSign
                    fun addUsage ((i, sels), pmap) = let
                        val arg = List.nth (args, i)
                    in
                        case ParamMap.find(vmap, VAR arg)
                         of NONE => pmap
                          | SOME p => let
                                val (p',l') = pathToList p
                                val q = listToPath (p', l'@sels)
                                fun addPathRef (p) =
                                    (case PMap.find (pmap,p)
                                      of SOME cnt => (addToRef(cnt, 1); pmap)
                                       | NONE => (case p
                                                   of (SEL(i, q)) => (addPathRef q)
                                                    (* Next case guaranteed to terminate because
                                                     * we always add all parameters to the pmap
                                                     *)
                                                    | x => (addPathRef x)))
                            in
                                addPathRef q
                            end
                    end
                    val pmap = List.foldr addUsage pmap sharedSig
                in
                    setInfo (enclFn, vmap, pmap, params, rets, sign, newParams, newRets)
                end
                  | updateCallSite (_) = ()
            in
                List.app updateCallSite (List.filter (fn (_, SITE{enclFn,...}) => case enclFn
                                                                                   of NONE => false
                                                                                    | SOME(f) => isCandidate f) sites)
            end
        else ();
        List.app setNewSignature candidateList
    end

  (* property for tracking whether a candidate function shares its callsites
   * with other functions. If it does, its parameters/arguments cannot be
   * trimmed during useless variable elimination (UVE) or we may have mismatched
   * calls.
   * TODO: It would be nice to push the UVE parameter elimination up into
   * the valid signature computation or as an extra pass over the shared
   * callsite candidate sets.
   *)
    local
      val {setFn, getFn, peekFn, ...} = CV.newProp (fn f => false)
    in
    fun isShared f = getFn f
    fun setShared f = (
        if !arityRaisingDebug andalso not(isShared f)
        then print (concat[CV.toString f, " is marked with shared call sites.\n"])
        else ();
        setFn (f, true))
    end

    (* for each candidate function, analyse the arguments of its call sites
     * For any candidate functions that share a call site, they will need to have
     * identical flattened signatures.*)
    fun analyse m = let
	  val candidates = gather m
          val sites = List.foldr (fn (f, s) => getSites f @ s) [] candidates
          (*
           * Find the sets (a) containing those callees. Create one site (b) with all of
           * those and the callees, and return the list of sets:
           * (candidateSets - a) union b
           *)
          fun candidateUnion (SITE{callees,...}, candidateSets) = let
              val _ = if !arityRaisingDebug
                      then print (concat["Proceesing site with callees: ",
                                         List.foldr (fn (callee, rr) => concat[CV.toString callee,
                                                                               " ", rr]) ""
                                         callees, "\n"])
                      else ()
              fun partByCallee (set) = (List.exists
                                            (fn (callee) => VSet.member (set, callee))
                                            callees)
              val (difference, remainder) = List.partition partByCallee candidateSets
              val calleeSet = VSet.addList (VSet.empty, callees)
	      val _ =  if List.length callees > 1
		       then List.app setShared callees
		       else ()
              val newSet = (case difference
                             of [] => calleeSet
                              | a => (if VSet.numItems (hd a) > 1
                                      then (List.app (fn (s) => VSet.app setShared s) a)
                                      else ();
                                      List.foldr VSet.union VSet.empty (calleeSet::a))
                           (* end case *))
          in
              newSet::remainder
          end
          val sharedSiteCandidates = List.foldr candidateUnion [] sites
          fun computeSignatures () = (
              signaturesChanged := false;
              ST.tick cntSignaturePasses;
              List.app computeValidSignatures sharedSiteCandidates;
              if !signaturesChanged andalso !multiPass
              then computeSignatures ()
              else ())
    in
        computeSignatures();
        candidates
    end

  (***** Usefulness *****)

  (* property for tracking the usefulness of a variable. All variables are assumed
   * useless until proven otherwise. Note that variables don't transition back to
   * useless once they've been identified as useful.
   *)
    local
      val {setFn, getFn, peekFn, ...} = CV.newProp (fn f => false)
    in
    fun setUseful f = setFn (f, true)
    fun getUseful f = getFn f
    end

    
  (* property for whether or not we've processed this function yet
   * the int corresponds to the round number, since we iterate scanning
   * until a fixpoint is reached
   *)
    datatype processing_state = UNPROCESSED | INPROCESS of int | DONE of int
    local
      val {setFn, getFn, peekFn, ...} = CV.newProp (fn f => UNPROCESSED)
    in
    fun setInProcess (f,i) = setFn (f, INPROCESS(i))
    fun setDone (f,i) = setFn (f, DONE(i))
    fun getProcessState f = getFn f
    end

    fun isEffectful (rhs, externs) = (
        case rhs
	 of C.Prim (primop) => not(PrimUtil.isPure primop)
	  | C.Update _ => true
	  | C.CCall (f, _) => let
                fun findCCall (cFun) = CV.same (CFunctions.varOf cFun, f)
                val cCall = List.filter findCCall externs
            in
                if List.length cCall = 1
                then not (CFunctions.isPure (List.hd cCall))
                else true
            end
	  | C.VPStore _ => true
	  | _ => false
    (* end case *))

    fun scanUseful (m, round) = let
	  val C.MODULE{body,externs,...} = m
	  val C.FB{f=main,params,rets,body} = body
	  val usefuls = ref (!escaping @ [main])
	  val changed = ref false
	  fun markUseful f = (
		if getUseful f then ()
		else (
		  if !arityRaisingDebug
		    then print (concat[
			CV.toString f, " is useful in round",
			Int.toString round, "\n"
		      ])
		    else ();
                  changed := true ;
                  setUseful f);
		case CV.kindOf f
		 of C.VK_Fun(_) =>
		    if not (List.exists (fn x => CV.same(x,f)) (!usefuls))
		      then usefuls := f :: !usefuls
		      else ()
		  | C.VK_Cont(_) =>
		    if not (List.exists (fn x => CV.same(x,f)) (!usefuls))
		      then usefuls := f :: !usefuls
		      else ()
		  | _ => ()
		(* end case *))
	  fun markCorresponding (a,b) = if getUseful a then markUseful b else ()

	  fun processLambda f = let
		val SOME(C.FB {body,params,rets,...}) = getFB f
		fun processBody () = (
		      setInProcess (f, round);
		      processExp body;
		      setDone (f, round))
		in
		  case getProcessState f
		   of UNPROCESSED => processBody()
		    | DONE(i) => if i = round then () else processBody()
		    | INPROCESS(i) =>  if i = round
		      (* For recursive function calls, we just return empty,
                       * assuming that we will pick upany additional information
                       * from the function when we return from the DFS.
		       *)
			then ()
			else processBody()
		  (* end case *)
		end
        and processExp (C.Exp (_, term)) = (case term
	    (* Scanning for usefulness is done bottom-up, so we process the body
	     * before bindings at hand.
	     *)
	       of C.Let ([var], rhs, body) => (
		    processExp body;
		    if isEffectful (rhs, externs) then setUseful var else ();
		    if getUseful var then processRhs rhs else ())
		| C.Let ([], rhs, body) => (
		    processExp body;
		    processRhs rhs)
		| C.Let (_, rhs, body) => (
		    processExp body;
		    processRhs rhs)
		| C.Fun (_, body) => processExp body
		| C.Cont (_, body) => processExp body
		| C.If(cond, e1, e2) => (
		    processExp e1;
		    processExp e2;
		    CondUtil.app markUseful cond)
		| C.Switch (x, cases, dflt) => (
		    List.app (fn (_, e) => processExp e) cases;
		    Option.app processExp dflt;
		    markUseful x)
		| C.Apply (f, args, rets) => (
		    case getFB f
		     of SOME(C.FB{params,rets=conts,...}) => let
			  val pairedArgs = ListPair.zip (params, args)
			  val pairedConts = ListPair.zip (conts, rets)
			  in
			    markUseful f;
			    processLambda f;
			    List.app markCorresponding pairedArgs ;
			    List.app markCorresponding pairedConts 
			  end
		      | NONE => (
			  List.app markUseful args;
			  List.app markUseful rets;
			  markUseful f)
		   (* end case *))	     
		| C.Throw (f, args) => (case getFB f
		     of SOME(C.FB{params,...}) => (let
			  val pairedArgs = ListPair.zip (params, args)
			  in
			    markUseful f;
			    processLambda f;
			    List.app markCorresponding pairedArgs
			  end)
		      | NONE => (List.app markUseful args; markUseful f)
		    (* end case *))
	      (* end case *))

	and processRhs rhs = (case rhs
	       of C.Var (vars) => List.app markUseful vars
		| C.Cast (_, v) => markUseful v
		| C.Const (_, _) => ()
		| C.Select (_, v) => markUseful v
		| C.Update (_, v, x) => (markUseful v; markUseful x)
		| C.AddrOf (_, v) => markUseful v
		| C.Alloc (_, vars) => List.app markUseful vars
		| C.Promote (v) => markUseful v
		| C.Prim p => PrimUtil.app markUseful p
		| C.CCall (f, args) => (markUseful f ; List.app markUseful args)
		| C.HostVProc => ()
		| C.VPLoad (_, v) => markUseful v
		| C.VPStore (_, v1, v2) => (markUseful v1; markUseful v2)
		| C.VPAddr (_, v) => markUseful v
	      (* end case *))
            
      (* We need to iterate to a fixpoint because it's frequent to have a
       * set of locals that are used in function bodies that we don't
       * realize correspond a useful variable binding until after 
       * we've already finished processing the binding for the current var
       *)
	fun process () = let
            val head = hd (!usefuls)
	    in
	      usefuls := tl (!usefuls);
	      processLambda (head) ;
	      if not(null(!usefuls))
		then process ()
	      else if !changed
		then scanUseful (m, round+1)
		else ()
	    end
	in
	  ST.tick cntUselessScanPasses;
	  process()
	end


  (***** Flattening *****)

  (* property for tracking whether a function was created during flattening.
   * this is important because we don't re-run CFA, so isEscaping is invalid
   * for it (says true even though it's false)
   *)
    local
      val {setFn, getFn, peekFn, ...} = CV.newProp (fn f => false)
    in
    fun setFlat f = setFn (f, true)
    fun isFlat f = getFn f
    end

    fun cfaGetLambdas(v) =
        case CFACPS.valueOf v
         of CFACPS.LAMBDAS(l) =>
            CPS.Var.Set.listItems l
          | _ => []

    (* If they are equal, or if one of the types is ANY, we are fine.
     * Any arises in two cases: 1) polymorphic types 2) unused parameters that are put 
     * in to keep a uniform calling convention.
     *)
    fun safeMergable ([],[]) = true
      | safeMergable (_,[]) = false
      | safeMergable ([],_) = false
     (* | safeMergable (x::xs, y::ys) = CPSTyUtil.validCast (x,y) andalso safeMergable (xs,ys)*)
      | safeMergable (x::xs, y::ys) = CPSTyUtil.match (x,y) andalso safeMergable (xs,ys)

    fun safeMergeTypes (CPSTy.T_Fun (p1,r1), CPSTy.T_Fun (p2,r2)) =
        if safeMergable(p1,p2) andalso safeMergable(r1,r2)
        then let
                val args = if (List.length p1 = List.length p2)
                           then (ListPair.map safeMergeTypes (p1,p2))
                           else [CPSTy.T_Any]
                val rets = if (List.length r1 = List.length r2)
                           then (ListPair.map safeMergeTypes (r1,r2))
                           else [CPSTy.T_Any]
            in
                CPSTy.T_Fun(args, rets)
            end
        else CPSTy.T_Fun([CPSTy.T_Any], [CPSTy.T_Any])
      | safeMergeTypes (CPSTy.T_Cont (p1), CPSTy.T_Cont (p2)) =
        if safeMergable(p1,p2)
        then let
                val args = if (List.length p1 = List.length p2)
                           then (ListPair.map safeMergeTypes (p1,p2))
                           else [CPSTy.T_Any]
            in
                CPSTy.T_Cont(args)
            end
        else CPSTy.T_Cont([CPSTy.T_Any])
      | safeMergeTypes (CPSTy.T_Tuple (b, t1), CPSTy.T_Tuple(b2,t2)) =
        if (List.length t1 = List.length t2)
        then CPSTy.T_Tuple(b, ListPair.map safeMergeTypes (t1,t2))
        else CPSTy.T_Any
      | safeMergeTypes (x,y) =
        if CPSTyUtil.soundMatch (x,y) andalso CPSTyUtil.soundMatch (y,x)
        then x
        else CPSTy.T_Any

    (*
     * Before performing the actual flattening, go through and figure out the new signatures.
     * Note that some of the return continuations may be flattening candidates, so we need
     * to first flatten all candidate functions then go back through the candidates and process
     * their return continuations to handle situations where we don't yet know what the
     * new signature will be on the return continuation at the time we're processing the
     * function that takes one as an argument.
     *)
    fun flattenSignatureInfo (C.MODULE{body=fb,...}) = let
        val changed = ref false
        (*
         * After we've flattened several functions, we need to transform any formals
         * or return continuations to have the new type. This is slightly tricky
         * because the functions can appear as fields in a tuple.
         * We also have to do some extra work to handle polymorphism - if we reach
         * a parameter in the target functions whose type differs, just promote it
         * to any. The type being different is an indicator that it's not actually
         * used in the calling function, but is just passed along.
         *)
        fun transformParam param = let
            fun getParamFunType (l) = let
                val funs = CPS.Var.Set.listItems l
                val lambdas = map CV.typeOf funs
                val _ = if !arityRaisingDebug
                        then print (concat["Merging signatures for fn types: ", String.concatWith "," (List.map (fn x => ((CPSTyUtil.toString x)^" ")) lambdas), " from variables: ", String.concatWith "," (List.map CPS.Var.toString funs), "\n"])
                        else ()
            in
                (* TODO: integrate knowledge of whether a param is "useless" or not before
                 * forcing a merge
                 *)
                if List.length lambdas = 0
                then CV.typeOf param
                else let
                        val l::lambdas = lambdas
                    in
                        foldr safeMergeTypes l lambdas
                    end
            end
            fun buildType (CPSTy.T_Tuple (heap, tys), cpsValues) = let
                fun updateSlot (origTy, cpsValue) = (
                    case cpsValue
                     of CFACPS.LAMBDAS(l) => getParamFunType l
                      | CFACPS.TUPLE (values) => buildType (origTy, values)
                      | _ => origTy
                (* end case *))
                val newTys = ListPair.map updateSlot (tys, cpsValues)
            in
                CPSTy.T_Tuple (heap, newTys)
            end
              | buildType (ty, _) = ty
        in
            case CFACPS.valueOf param
             of CFACPS.LAMBDAS(l) => let
                    val newType = getParamFunType l
                    val _ = if !arityRaisingDebug
                            then print(concat(["Merged signature is: ", CPSTyUtil.toString newType, "\n"]))
                            else ()
                in
                    if CPSTyUtil.equal (CV.typeOf param, newType)
                    then ()
                    else (changed := true;
                          CV.setType (param, newType))
                end

              | CFACPS.TUPLE(values) => let
                    val newType = buildType (CV.typeOf param, values)
                in
                    if CPSTyUtil.equal (CV.typeOf param, newType)
                    then ()
                    else (changed := true;
                          CV.setType (param, newType))
                end
              | _ => ()
        end
        and handleLambda(func as C.FB{f, params, rets, body}) =
	    if not (isCandidate f)
            then walkBody (body, handleLambda)
	    else let
                    val _ = if !arityRaisingDebug
                            then print (concat["Generating new signature for: ",
                                               CV.toString f, " ORIG: ",
                                               CPSTyUtil.toString (CV.typeOf f)])
                            else ()
		    val {vmap, pmap, params, rets, sign, ...} = getInfo f
		    val newParams = computeParamList (params, vmap, sign)
                    val newParams = if not(isShared f)
                                    then List.filter getUseful newParams
                                    else newParams
                    val newRets = if not(isShared f)
                                  then List.filter getUseful rets
                                  else rets
                    val origType = CV.typeOf f
		    val newType = case origType
                                   of CTy.T_Fun _ => CTy.T_Fun (List.map CV.typeOf newParams, List.map CV.typeOf newRets)
                                    | CTy.T_Cont _ => CTy.T_Cont (List.map CV.typeOf newParams)
                                    | _ => raise Fail (concat["non-function type marked as candidate: ", CV.toString f, " : ",
                                                              CPSTyUtil.toString origType])
                    val _ = if !arityRaisingDebug
                            then print (concat[" NEW: ", CPSTyUtil.toString (newType), "\n"])
                            else ()
                    val _ = CV.setType (f, newType)
                    val _ = setFlat (f)
		    val _ = setInfo (f, vmap, pmap, params, rets, sign, SOME(newParams), SOME(newRets))
	        in
                    walkBody (body, handleLambda)
	        end
        and handleParams(func as C.FB{f, params, rets, body}) =
	    if not (isCandidate f)
            then let
                    val _ = if !arityRaisingDebug
                            then print (concat["Flattening non-candidate params ",
                                               CV.toString f, " orig: ",
                                               CPSTyUtil.toString (CV.typeOf f), "\n"])
                            else ()
                    val _ = List.app transformParam params
                    val _ = List.app transformParam rets
                    val origType = CV.typeOf f
		    val newType = case origType
                                   of CTy.T_Fun _ => CTy.T_Fun (List.map CV.typeOf params, List.map CV.typeOf rets)
                                    | CTy.T_Cont _ => CTy.T_Cont (List.map CV.typeOf params)
                                    | _ => raise Fail (concat["non-function type marked as candidate: ", CV.toString f, " : ",
                                                              CPSTyUtil.toString origType])
                    val _ = CV.setType (f, newType)
                    val _ = if !arityRaisingDebug
                            then print (concat[" new: ", CPSTyUtil.toString newType, "\n"])
                            else ()
                in
                    walkBody (body, handleParams)
                end
            else let
                    val _ = if !arityRaisingDebug
                            then print (concat["Flattening candidate params ",
                                               CV.toString f, " orig: ",
                                               CPSTyUtil.toString (CV.typeOf f), "\n"])
                            else ()
		    val {vmap, pmap, params, rets, sign, 
                         newParams=SOME(newParams), newRets=SOME(newRets)} = getInfo f
                    (* Need to transform the originals as well because they're used for the
                     * type coercions later in the flattened applications.
                     *)
                    val _ = List.app transformParam (List.filter getUseful params)
                    val _ = List.app transformParam (List.filter getUseful rets)
                    val _ = List.app transformParam newParams
                    val _ = List.app transformParam newRets
                    val origType = CV.typeOf f
		    val newType = case origType
                                   of CTy.T_Fun _ => CTy.T_Fun (List.map CV.typeOf newParams, List.map CV.typeOf newRets)
                                    | CTy.T_Cont _ => CTy.T_Cont (List.map CV.typeOf newParams)
                                    | _ => raise Fail (concat["non-function type marked as candidate: ", CV.toString f, " : ",
                                                              CPSTyUtil.toString origType])
                    val _ = CV.setType (f, newType)
		    val _ = setInfo (f, vmap, pmap, params, rets, sign, SOME(newParams), SOME(newRets))
                    val _ = if !arityRaisingDebug
                            then print (concat[" new: ", CPSTyUtil.toString newType, "\n"])
                            else ()
                in
                    walkBody (body, handleParams)
                end
        and walkBody (C.Exp(_, e), p) = (
            case e
             of C.Let (_, _, e) => walkBody (e, p)
              | C.Fun (lambdas, body) => (List.app p lambdas; walkBody (body, p))
              | C.Cont (f, body) => (p f; walkBody (body, p))
              | C.If (_, e1, e2) => (walkBody (e1, p); walkBody (e2, p))
              | C.Switch (_, cases, body) => (
                List.app (fn (_, e) => walkBody (e, p)) cases;
                Option.app (fn x => walkBody (x,p)) body)
              | C.Apply (_, _, _) => ()
              | C.Throw (_, _) => ())
        (*
         * If we change the signature of a function that was passed in as an argument
         * to an earlier function, we may need to go back and fix it up. Therefore, we
         * iterate until we reach a fixpoint.
         *)
        fun loopParams (fb) = (
            handleParams (fb);
            if (!changed)
            then (changed := false; loopParams (fb))
            else ())
    in
        handleLambda(fb);
        loopParams(fb)
    end

    (*
     * Flattening can change parameter types in function bodies. To propagate
     * those changes along, we use a quick function to fix up let bindings.
     * Note that we skip any lets with multiple LHS's.
     *)
    fun fixLet (lhs, rhs) = let
        (* Only return a changed type if it's likely to be different.
         * For many RHS values, it's neither straightforward nor necessary to
         * compute a new type value, as it can't have been changed by the
         * flattening transformation.
         *)
        fun typeOfRHS(C.Var ([v])) = SOME (CV.typeOf v)
          | typeOfRHS(C.Var (vars)) = NONE
          | typeOfRHS(C.Cast (typ, var)) = (* if the cast is or contains a function type,
                                            * we may have updated it in an incompatible way
                                            * for the cast, so just fill in our type.
                                            * This frequently happens around the generated _cast
                                            * for ropes code
                                            *)
            let
                val rhsType = CV.typeOf var
                fun cleanup (CTy.T_Tuple (b, dstTys), CTy.T_Tuple (b', srcTys)) = let
                    val dstLen = List.length dstTys
                    val srcLen = List.length srcTys
                    val (dst', src') = (
                        case Int.compare (dstLen, srcLen)
                         of LESS => (dstTys @ (List.tabulate (srcLen-dstLen, (fn (x) => CTy.T_Any))), srcTys)
                          | EQUAL => (dstTys, srcTys)
                          | GREATER => (dstTys, srcTys @ (List.tabulate (dstLen-srcLen, (fn (x) => CTy.T_Any)))))
                in
                    CTy.T_Tuple (b, ListPair.mapEq cleanup (dst', src'))
                end
                  | cleanup (dst as CTy.T_Fun(_, _), src as CTy.T_Fun (_, _)) =
                    if CPSTyUtil.soundMatch (dst, src)
                    then dst
                    else src
                  | cleanup (dst as CTy.T_Cont(_), src as CTy.T_Cont (_)) =
                    if CPSTyUtil.soundMatch (dst, src)
                    then dst
                    else src
                  | cleanup (dst, _) = dst
                val result = cleanup (typ, rhsType) 
            in
                SOME (result)
            end
          | typeOfRHS(C.Const (_, typ)) = SOME(typ)
          | typeOfRHS(C.Select (i, v)) = (
            (* Select is often used as a pseudo-cast, so only "change" the type if we've 
             * come across a slot that is a function type, which we might have updated.
             *)
            case CV.typeOf v
             of CTy.T_Tuple (_, tys) => (
                case List.nth (tys, i)
                 of newTy as CTy.T_Fun (_, _) => SOME (newTy)
                  | newTy as CTy.T_Cont _ => SOME (newTy)
                  | _ => NONE
                (* end case *))
              | CTy.T_Deque => NONE
              | ty => raise Fail (concat [CV.toString v,
                                          " was not of tuple type, was: ",
                                          CPSTyUtil.toString ty])
            (* end case *))
          | typeOfRHS(C.Update (_, _, _)) = NONE
          | typeOfRHS(C.AddrOf (i, v)) = (
            (* Select is often used as a pseudo-cast, so only "change" the type if we've 
             * come across a slot that is a function type, which we might have updated.
             *)
            case CV.typeOf v
             of CTy.T_Tuple (_, tys) => (
                case List.nth (tys, i)
                 of newTy as CTy.T_Fun (_, _) => SOME (CTy.T_Addr(newTy))
                  | newTy as CTy.T_Cont _ => SOME (CTy.T_Addr(newTy))
                  | _ => NONE
                (* end case *))
              | CTy.T_Deque => NONE
              | ty => raise Fail (concat [CV.toString v,
                                          " was not of tuple type, was: ",
                                          CPSTyUtil.toString ty])
            (* end case *))
          | typeOfRHS(C.Alloc (CPSTy.T_Tuple(b, tys), vars)) = let
                (*
                 * Types of items stored into an alloc are frequently wrong relative to
                 * how they're going to be used (i.e. a :enum(0) in for a ![any, any]).
                 * Only update function types.
                 *)
                fun chooseType (ty, vTy as CTy.T_Fun(_, _)) = vTy
                  | chooseType (ty, vTy as CTy.T_Cont _) = vTy
                  | chooseType (ty as CTy.T_Tuple(_,tys), vTy as CTy.T_Tuple(b,vTys)) =
                    CTy.T_Tuple(b, ListPair.map chooseType (tys, vTys))
                  | chooseType (ty, _) = ty
            in
                SOME (CPSTy.T_Tuple(b, ListPair.map chooseType (tys, (List.map CV.typeOf vars))))
            end
          | typeOfRHS(C.Alloc (_, vars)) = raise Fail "encountered an alloc that didn't originally have a tuple type."
          | typeOfRHS(C.Promote (v)) = SOME (CV.typeOf v)
          | typeOfRHS(C.Prim (prim)) = NONE (* do I need to do this one? *)
          | typeOfRHS(C.CCall (cfun, _)) = NONE
          | typeOfRHS(C.HostVProc) = NONE
          | typeOfRHS(C.VPLoad (_, _)) = NONE
          | typeOfRHS(C.VPStore (_, _, _)) = NONE
          | typeOfRHS(C.VPAddr (_, _)) = NONE
    in
        (case lhs
          of [v] => (
             case typeOfRHS (rhs)
              (* Even if we got a new type back, if the existing one is equal or more
               * specific, stick with the old one.
               *)
              of SOME(ty) => (if !arityRaisingDebug
                              then print (concat["Changing ", CV.toString v,
                                                 " from: ", CPSTyUtil.toString (CV.typeOf v),
                                                 " to: ", CPSTyUtil.toString ty, "\n"])
                              else ();
                              CV.setType (v, ty))
               | NONE => ()
             (* end case *))
           | _ => ()
        (* end case *))
    end

    (* walk down the tree and:
     * 1) turn candidate functions into their specialized version
     * 2) change any calls to candidate functions (or known call sites to
     * candidate functions) to use the new args/rets
     *)
    fun flatten (C.MODULE{name,externs,body=(C.FB{f=main,params=modParams,rets=modRets,body=modBody})}) = let
          fun genUseless(useless, body) = let
              val typ = CV.typeOf useless
              fun cast () = let
                  val temp = CV.new ("any", CTy.T_Any)
              in
                  C.mkLet ([temp], C.Const(Literal.Enum(0w0), CTy.T_Any),
                           C.mkLet ([useless], C.Cast (typ, temp), body))
              end
          in
              case typ
               of CTy.T_Any => C.mkLet ([useless], C.Const(Literal.Enum(0w0), CTy.T_Any), body)
                | CTy.T_Enum (_) => C.mkLet ([useless], C.Const(Literal.Enum(0w0), typ), body)
                | CTy.T_Raw(RawTypes.T_Byte) => C.mkLet ([useless], C.Const(Literal.Int(0), typ), body)
                | CTy.T_Raw(RawTypes.T_Short) => C.mkLet ([useless], C.Const(Literal.Int(0), typ), body)
                | CTy.T_Raw(RawTypes.T_Int) => C.mkLet ([useless], C.Const(Literal.Int(0), typ), body)
                | CTy.T_Raw(RawTypes.T_Long) => C.mkLet ([useless], C.Const(Literal.Int(0), typ), body)
                | CTy.T_Raw(RawTypes.T_Float) => C.mkLet ([useless], C.Const(Literal.Float(FloatLit.zero (true)), typ), body)
                | CTy.T_Raw(RawTypes.T_Double) => C.mkLet ([useless], C.Const(Literal.Float(FloatLit.zero (true)), typ), body)
                | CTy.T_Raw(RawTypes.T_Vec128) => C.mkLet ([useless], C.Const(Literal.Enum(0w0), typ), body)
                | CTy.T_Tuple (_, _) => cast ()
                | CTy.T_Addr (_) => cast ()
                | CTy.T_Fun (_, _) => cast ()
                | CTy.T_Cont _ => cast ()
                | CTy.T_CFun (_) => cast ()
                | CTy.T_VProc => cast()
                | CTy.T_Deque => cast()
          end
	  fun flattenApplyThrow (ppt, encl, g, args, retArgs) = let
              val lambdas = cfaGetLambdas g
              fun matchTypes (paramType::paramTypes, arg::orig, accum, final) =
                  let
                      val argType = CV.typeOf arg
                  in
                      if CPSTyUtil.soundMatch (argType, paramType)
                      then matchTypes (paramTypes, orig, arg::accum, final)
                      else let
                              val newParamType = safeMergeTypes (argType, paramType)
                              val typed = CV.new ("coerced", newParamType)
                              val _ = if !arityRaisingDebug
                                      then print (concat["Coercing from: ",
                                                         CPSTyUtil.toString argType,
                                                         " to: ",
                                                         CPSTyUtil.toString paramType,
                                                         " final (safe): ",
                                                         CPSTyUtil.toString newParamType,
                                                         " for argument: ",
                                                         CV.toString arg, "\n"])
                                      else ()
                              val _ = if getUseful arg then setUseful typed else ()
                          in
                              C.mkLet ([typed], C.Cast(newParamType, arg),
                                       matchTypes (paramTypes, orig, typed::accum, final))
                          end
                  end
                | matchTypes (paramTypes, [], accum, final) =
                  final (rev accum)
                | matchTypes (_, _, accum, final) =
                  raise Fail (concat["Can't happen - call to method had mismatched arg/params.",
                                     CV.toString g])
              fun translateArgs (v::vl, accum, final) =
                  if shouldSkipUseless v
                  then (let
                            val useless = CV.copy v
                        in
                            genUseless (useless, translateArgs (vl, useless::accum, final))
                        end)
                  else translateArgs (vl, v::accum, final)
                | translateArgs ([], accum, final) =
                  final (rev accum)
          in
              if isCandidate g orelse (List.length lambdas > 0 andalso
                                       isCandidate (List.hd lambdas))
	      then let
                  val f = if isCandidate g
                          then g
                          else List.hd lambdas
                  val _ = if !arityRaisingDebug
                          then print (concat["Flattening call to: ", CV.toString f,
                                             if isCandidate g then " candidate" else " non-candidate",
                                             " through variable: ", CV.toString g, "\n"])
                          else ()
		  val {sign, params, rets, newRets=SOME(newRets),
                       newParams=SOME(fParams), ...} = getInfo f
                  val (callParamTypes, retTypes) = case CV.typeOf g
                                                    of CPSTy.T_Fun(callParamTypes, retTypes) => (callParamTypes, retTypes)
                                                     | CPSTy.T_Cont(callParamTypes) => (callParamTypes, [])
                                                     | _ => raise Fail (concat["non-function type passed to flattenApplyThrow: ", CV.toString g,
                                                                               ":", CPSTyUtil.toString (CV.typeOf g)])
		  fun genCall (sign, params, newArgs, progress, args') =
                        if null sign orelse null params
			  then (case retArgs
			     of SOME(retArgs) => let
                                    val filteredRetArgs = ListPair.foldr
                                        (fn (a,b,rr) => if getUseful a orelse isShared f
                                                        then b::rr
                                                        else rr)
                                        []
                                        (newRets, retArgs)
                                in
                                    matchTypes (callParamTypes, rev newArgs, [],
                                                fn finalArgs =>
                                                   matchTypes (retTypes, filteredRetArgs, [],
                                                            fn newRets =>
                                                               translateArgs (newRets, [],
                                                                           fn finalRets =>
                                                                              C.Exp(ppt, C.Apply(g, finalArgs, finalRets)))))
                                end
			      | NONE => matchTypes (callParamTypes, rev newArgs, [], 
                                                    fn finalArgs => C.Exp(ppt, C.Throw(g, finalArgs)))
			    (* end case *))
			  else let
			    fun genResult (varBase, path) =
                                  if length path = 0
				  then genCall (tl sign, tl params, varBase :: newArgs, NONE, args')
				  else (case peekAlias ((hd path), varBase)
                                       of SOME (v') => genCall (sign, params, newArgs, SOME (v', tl path), args')
                                        | NONE => let
				              val newType = (
                                                  case CV.typeOf varBase
					           of CTy.T_Tuple(_, types) => List.nth (types, (hd path))
					            | CTy.T_Any => raise Fail (concat[
						                               "SEL into any of var: ", CV.toString varBase,
						                               " probably flattening var that isn't guaranteed to be that type.\n"
						                              ])
					            | _ => raise Fail (concat[
                                                                       "SEL from non tuple/any type: ",
                                                                       CV.toString varBase])
				              (* end case *))
				              val newVar = CV.new ("letFlat", newType)
				              val rhs = C.Select (hd path, varBase)
                                              val _ = addVarToMap (encl, newVar, hd path, varBase)
				          in
				              if length path = 1
					      then C.mkLet ([newVar], rhs,
                                                            genCall (tl sign, tl params, newVar :: newArgs, NONE, args'))
					      else C.mkLet ([newVar], rhs,
					                    genCall (sign, params, newArgs, SOME (newVar, tl path), args'))
                                          end
                                      (* end case *))
			    in
			      case progress
			       of SOME(base,l) => genResult (base, l)
				| NONE => let
				    val (whichBase, path)::_ = sign
                                    val param = hd params
				    val varBase = List.nth (args', whichBase)
				    in
                                      (* Flattened functions will lose any useless parameters.
                                       * We know they only have known call sites (by construction).
                                       *)
                                      if shouldSkipUseless param andalso not(isShared f)
                                      then genCall (tl sign, tl params, newArgs, NONE, args')
				      else genResult (varBase, path)
				    end
			      (* end case *)
                            end
                  fun cleanupArgsBeforeCall (sign, params, newArgs, progress,
                                             paramType::paramTypes, arg::orig, accum) =
                      let
                          val argType = CV.typeOf arg
                      in
                          if CPSTyUtil.soundMatch (argType, paramType)
                          then cleanupArgsBeforeCall (sign, params, newArgs, progress, paramTypes, orig, arg::accum)
                          else let
                                  val typed = CV.new ("coerced", paramType)
                                  val _ = if !arityRaisingDebug
                                          then print (concat["Coercing from: ",
                                                             CPSTyUtil.toString argType,
                                                             " to: ",
                                                             CPSTyUtil.toString paramType,
                                                             " for argument: ",
                                                             CV.toString arg, "\n"])
                                          else ()
                              in
                                  C.mkLet ([typed], C.Cast(paramType, arg),
                                           cleanupArgsBeforeCall (sign, params, newArgs, progress,
                                                                  paramTypes, orig, typed::accum))
                              end
                      end
                    | cleanupArgsBeforeCall (sign, params, newArgs, progress, paramTypes, [], accum) =
                      genCall (sign, params, newArgs, progress, rev accum)
                    | cleanupArgsBeforeCall (sign, params, newArgs, progress, _, _, accum) =
                      raise Fail (concat["Can't happen - call to method had mismatched arg/params.",
                                         CV.toString g])
                  val paramTypes = List.map CV.typeOf params
 		  in
                    (* Often, original tupled arguments are of type :any instead of what
                     * they will be at the landing site of the call, relying on Apply to
                     * implicitly cast them. Since we're checking types in our flat-sels
                     * above, if the original argument is not of the type it would have
                     * when the Apply lands, we cast it here and use that instead.
                     *)
                    cleanupArgsBeforeCall (sign, fParams, [], NONE, paramTypes, args, [])
		  end
		else let 
                        (* Not a call to a candidate function. Keep arguments in place,
                         * but also make sure that they don't need to be translated to match
                         * the appropriate types. Args may have been retyped during flattening
                         * of the enclosing function.
                         *)
                        val (paramTypes, retTypes) = case CV.typeOf g
                                                      of CPSTy.T_Fun(callParamTypes, retTypes) => (callParamTypes, retTypes)
                                                       | CPSTy.T_Cont(callParamTypes) => (callParamTypes, [])
                                                       | _ => raise Fail (concat["non-function type passed to flattenApplyThrow non-candidate: ", CV.toString g,
                                                                                 ":", CPSTyUtil.toString (CV.typeOf g)])
                    in
                        matchTypes (paramTypes, args, [],
                          fn newArgs =>
                             case retArgs
                              of SOME(retArgs) =>
                                 matchTypes (retTypes, retArgs, [],
                                          fn newRets =>
                                             translateArgs (newArgs, [],
                                              fn x => translateArgs (newRets, [],
                                                fn y => C.Exp(ppt, C.Apply(g, x, y)))))
                               | NONE => translateArgs (newArgs, [],
                                           fn x => C.Exp (ppt, C.Throw(g, x))))
                    end
          end
          and shouldSkipUseless (v) = if getUseful v
		then false
		else (ST.tick (cntUselessElim); true)
          and findInSign (_, _, _, []) = NONE
            | findInSign (n, s::sign, path, params) = 
              if samePath(path, listToPath s)
              then SOME(List.nth (params, n))
              else findInSign(n+1,sign, path, params)
            | findInSign (n, [], _, _) = NONE
          and addVarToMap (candidate, newVar, sel, baseVar) =
            if isCandidate candidate
            then let
                    val {vmap, pmap, params, rets, sign, newParams, newRets} = getInfo candidate
                in
                    case ParamMap.find (vmap, VAR (baseVar))
                     of SOME(path) => (
                        setInfo (candidate, ParamMap.insert (vmap, VAR newVar, SEL(sel, path)),
                                 PMap.insert (pmap, SEL(sel, path), ref 0),
                                 params, rets, sign, newParams, newRets);
                        setParent (newVar, candidate))
                      | NONE => ()
                end
            else ()
          (* look up path in defining function of selectee *)
          and peekAlias (i, y) = (
              case getParent y
               of SOME(encl) => (
                  if not(isCandidate encl)
                  then NONE
                  else let
                          val {vmap, sign, newParams=SOME(newParams), ...} = getInfo encl
                      in
                          case ParamMap.find (vmap, VAR (y))
                           of SOME(path) => (findInSign(0, sign, SEL (i, path), newParams))
                            | NONE => NONE
                      end)
                | NONE => NONE
          (* end case *))
          and findAlias (v, encl, i, y) =
              if not(isCandidate encl)
              then NONE
              else let
                      val {vmap, sign, newParams=SOME(newParams), ...} = getInfo encl
                  in
                      case ParamMap.find (vmap, VAR (v))
                       of SOME(path) => (findInSign(0, sign, path, newParams))
                        | NONE => peekAlias (i, y)
                          
                  end
	  and walkExp(encl, newParams, C.Exp(ppt,e)) = (case e
		 of (C.Let([v], rhs, e)) => (
		    (* If v has been promoted to a param or its
		     * use count is now zero, omit it
		     *)
		      if List.exists (fn x => CV.same(x, v)) newParams
		      orelse shouldSkipUseless (v)
			then walkExp (encl, newParams, e)
			else (case rhs
                               of C.Select(i, y) => (
                                  case findAlias (v, encl, i, y)
                                   of SOME(v') => (fixLet ([v], C.Var([v']));
                                                   C.mkLet ([v], C.Var ([v']),
                                                            walkExp (encl, newParams, e)))
                                    | NONE => (fixLet ([v], rhs);
                                               C.mkLet([v], rhs, walkExp (encl, newParams, e)))
                                  (* end case *))
                                | C.Cast(ty,x) => (fixLet ([v], rhs);
                                                   C.mkLet ([v], C.Cast (CV.typeOf v, x),
                                                            walkExp (encl, newParams, e)))
                                | _ => (fixLet ([v], rhs);
                                        C.mkLet([v], rhs, walkExp (encl, newParams, e)))
                             (* end case *)))
		  | (C.Let(vars, rhs, e)) =>
		      if List.exists (fn v => List.exists (fn x => CV.same(x, v)) newParams) vars
			then raise Fail ("Can't lift variable from multi-bind on LHS of let")
			else C.mkLet(vars, rhs, walkExp (encl, newParams, e))
		  | (C.Fun(fbs, e)) => let
		      val newfuns = List.foldr (fn (f,rr) => handleLambdaBody (f,false) :: rr) [] fbs
                      val newfuns' = List.filter (fn (C.FB{f,...}) => not(shouldSkipUseless f)) newfuns
		      in
                        if null (newfuns')
                        then walkExp (encl, newParams, e)
                        else C.mkFun (newfuns', walkExp (encl, newParams, e))
		      end
		  | (C.Cont(fb, e)) => (
                    let
                        val single as C.FB{f=single',...} = handleLambdaBody (fb, true)
                    in
			if shouldSkipUseless single'
			then walkExp (encl, newParams, e)
			else C.mkCont(single, walkExp (encl, newParams, e))
                    end)
		  | (C.If(x, e1, e2)) =>
		      C.mkIf(x, walkExp (encl, newParams, e1), walkExp (encl, newParams, e2))
		  | (C.Switch(x, cases, dflt)) =>
		      C.mkSwitch(x,
			         List.map (fn (tag,exp) => (tag,walkExp (encl, newParams, exp))) cases,
			         Option.map (fn (f) => walkExp (encl, newParams, f)) dflt)
		  | (C.Apply(g, args, rets)) => flattenApplyThrow (ppt, encl, g, args, SOME(rets))
		  | (C.Throw(k, args)) => flattenApplyThrow (ppt, encl, k, args, NONE)
		(* end case *))

        (* Returns flattened version of candidate functions *)
        and handleLambdaBody (func as C.FB{f, params, rets, body}, isCont) =
            if not (isCandidate f)
            then C.FB{f=f, params=params, rets=rets, body=walkExp (f, params, body)}
            else let
		  val {params, rets, newParams=SOME(newParams), newRets=SOME(newRets), ...} = getInfo f
		  val body = walkExp (f, newParams, body)
		  val lambda = C.mkLambda(C.FB{f=f, params=newParams, rets=newRets, body=body}, isCont)
                in
                    setFB (f, lambda);
                    lambda
                end
            
	in
	  C.MODULE{
	      name=name, externs=externs,
	      body = C.mkLambda(C.FB{
                  f=main,params=modParams,rets=modRets,
                  body= walkExp (main, modParams, modBody)
		}, false)
	    }
	end
        
    (*
     * Given our incremental approach to flattening and useless elimination, it would be
     * technically better to iterate CFA+flat+useless+Census+contract to a fixpoint. However,
     * that's really slow. We instead just iterate this cleanup pass to a fixpoint.
     *
     * Flatten+useless elim can leave around useCnt=0 params on flattened functions.
     * This removes them, cleans up the types, and cleans up the call sites.
     * It also cleans up any unused let bindings.
     *
     * Do not clean up arguments on:
     * - non-candidate functions (we don't necessarily know all of their call sites)
     * - those with shared signatures (we did the best we could during flattening)
     * - functions passed as arguments (i.e. return continuations). (we would need
     * to fix up the types all the way through the functions, which means yet another
     * pass)
     *)
    fun skipParamDebug f = 
        if not(isFlat f)
        then print ("Skipping param cleanup for " ^ CV.toString f ^ " because it is not flat\n")
        else if isShared f
             then print ("Skipping param cleanup for " ^ CV.toString f ^ " because it is shared\n")
             else if CV.useCount f > CV.appCntOf f
                  then print ("Skipping param cleanup for " ^ CV.toString f ^ " because its use count is greater than its app count\n")
                  else print ("Performing param cleanup for " ^ CV.toString f)
     
     
    fun skipParamCleanup (f) = (if !arityRaisingDebug then skipParamDebug f else ();
        not(isFlat f) orelse
        isShared f orelse
        (CV.useCount f > CV.appCntOf f))
    fun cleanup (C.MODULE{name,externs,body=(C.FB{f=main,params=modParams,rets=modRets,body=modBody})}) = let
        fun decCountsRHS (rhs) = (
            case rhs
             of C.Var (vars) => List.app Census.decUseCnt vars
	      | C.Cast (_, v) => Census.decUseCnt v
	      | C.Const (_, _) => ()
	      | C.Select (_, v) => Census.decUseCnt v
	      | C.Update (_, v, x) => (Census.decUseCnt v; Census.decUseCnt x)
	      | C.AddrOf (_, v) => Census.decUseCnt v
	      | C.Alloc (_, vars) => List.app Census.decUseCnt vars
	      | C.Promote (v) => Census.decUseCnt v
	      | C.Prim p => PrimUtil.app Census.decUseCnt p
	      | C.CCall (f, args) => (Census.decUseCnt f ; List.app Census.decUseCnt args)
	      | C.HostVProc => ()
	      | C.VPLoad (_, v) => Census.decUseCnt v
	      | C.VPStore (_, v1, v2) => (Census.decUseCnt v1; Census.decUseCnt v2)
	      | C.VPAddr (_, v) => Census.decUseCnt v
        (* end case *))
        fun cleanupExp (exp as C.Exp(ppt, e)) = (
            case e
             of C.Let ([x], rhs, e) => (if CV.useCount x > 0 orelse isEffectful (rhs, externs)
                                        then C.mkLet ([x], rhs, cleanupExp e)
                                        else (ST.tick cntUnusedStmt; decCountsRHS rhs; cleanupExp e))
              | C.Let ([], rhs, e) => C.mkLet ([], rhs, cleanupExp e)
              | C.Let (vars, C.Var(rhsV), e) => let
                    fun checkOne (v, r) =
                        if CV.useCount v = 0
                        then (ST.tick cntUnusedStmt; true)
                        else (Census.decUseCnt r; false)
                    val paired = ListPair.zip (vars, rhsV)
                    val filtered = List.filter checkOne paired
                    val (vars', rhsV') = ListPair.unzip filtered
                in
                    if length vars' = 0
                    then cleanupExp e
                    else C.mkLet (vars', C.Var(rhsV'), cleanupExp e)
                end
              | C.Let (_, _, _) => raise Fail "let-binding had multiple LHS but not a multi-var-bind RHS."
              | C.Fun (lambdas, body) => let
                    val lambdas = List.map (fn x => cleanupLambda (x,false)) lambdas
                in
                    C.mkFun (lambdas, cleanupExp body)
                end
              | C.Cont (f, body) => C.mkCont (cleanupLambda (f, true), cleanupExp body)
              | C.If (v, e1, e2) => C.mkIf (v, cleanupExp e1, cleanupExp e2)
              | C.Switch (v, cases, body) => C.mkSwitch(v, List.map (fn (tag,e) => (tag, cleanupExp e))
                                                                    cases, Option.map cleanupExp body)
              | C.Apply (f, args, retArgs) => (
                if skipParamCleanup f
                then exp
                else case getFB f
                      of SOME(C.FB{params,rets,...}) => let
                             val newArgs = ListPair.foldr (fn (a,b,rr) => if CV.useCount a > 0 then b::rr
                                                                  else (ST.tick cntUnusedArg; Census.decUseCnt b ; rr))
                                                          [] (params, args)
                             val newRets = ListPair.foldr (fn (a,b,rr) => if CV.useCount a > 0 then b::rr
                                                                  else (ST.tick cntUnusedArg; Census.decUseCnt b ; rr))
                                                          [] (rets, retArgs)
                         in
                             case CV.kindOf f
                              of CPS.VK_Fun(_) => C.mkApply (f, newArgs, newRets)
                               | _ => raise Fail (concat["Attempt to to variable: ", CV.toString f,
                                                         " of kind: ", C.varKindToString (CV.kindOf f)])
                         end
                       | NONE => exp)
              | C.Throw (k, args) => (
                if skipParamCleanup k
                then exp
                else case getFB k
                      of SOME(C.FB{params,...}) => 
                         C.mkThrow(k,
                                   ListPair.foldr (fn (a,b,rr) => if CV.useCount a > 0 then b::rr
                                                                  else (ST.tick cntUnusedArg; Census.decUseCnt b ; rr))
                                                  [] (params, args))
                       | NONE => exp)
                (* end case *))
        and cleanupLambda (lambda as C.FB{f, params, rets, body}, isCont) =
            if skipParamCleanup f
            then C.mkLambda(C.FB{f=f,params=params,rets=rets,body=cleanupExp body}, isCont)
            else let
                    val params' = List.filter (fn p => (CV.useCount p) > 0) params
                    val rets' = List.filter (fn p => (CV.useCount p) > 0) rets
                    val _ = ST.bump (cntUnusedParam, ((length params) + (length rets)) -
                                                     ((length params') + (length rets')))
                    val origType = CV.typeOf f
		    val newType = case origType
                                   of CTy.T_Fun _ => CTy.T_Fun (List.map CV.typeOf params', List.map CV.typeOf rets')
                                    | CTy.T_Cont _ => CTy.T_Cont (List.map CV.typeOf params')
                                    | _ => raise Fail (concat["non-function type marked as candidate: ", CV.toString f, " : ",
                                                              CPSTyUtil.toString origType])
                    val _ = CV.setType (f, newType)
                    val fb = C.FB{f=f,params=params',rets=rets',body=cleanupExp body}
                in
                    C.mkLambda(fb, isCont)
                end
    in
        C.MODULE{
	name=name, externs=externs,
	body = C.mkLambda(C.FB{
                          f=main,params=modParams,rets=modRets,
                          body= cleanupExp (modBody)
		         }, false)
	}
    end

    fun cleanupLoop (body) = let
        fun getCounters() = (ST.count cntUnusedStmt) +
                            (ST.count cntUnusedParam) +
                            (ST.count cntUnusedArg)
        val start = getCounters()
        val _ = ST.tick cntCleanupPasses
        val body' = cleanup (body)
    in
        if getCounters() <> start
        then cleanupLoop (body')
        else body'
    end

    fun dump m prefix = 
        if !dumpArityRaising
        then let val file = TextIO.openOut(prefix ^ "ArityRaisingOutput.cps")
             in PrintCPS.output(file, m)
             end
        else ()
  (***** Transformation *****)

    fun transform m = if !enableArityRaising
	  then let
	    val _ = dump m "pre"
	    val candidates = analyse m
            val _ = scanUseful (m, 0)
            val _ = flattenSignatureInfo m
	    val m' = flatten m
            (* FIXME: should maintain census counts! *)
	    val _ = Census.census m'
            val m' = cleanupLoop m'
            val _ = dump m' "post"
	    in
	      if !arityRaisingDebug
		then List.app printCandidate candidates
		else ();
              m'
	    end
	  else m

  end
