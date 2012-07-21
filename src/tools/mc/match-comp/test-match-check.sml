(* test-match-check,sml
 *
 * COPYRIGHT (c) 2010 The Manticore Project (http://manticore.cs.uchicago.edu/)
 * All rights reserved.
 *
 *)

structure TestMatchCheck = struct

(* pretty printers *)

  val pat = MatchCheck.patToString
  val patmat = MatchCheck.patmatToString

(* constants and utilities for testing *)

  val zro = ASTUtil.mkInt 0
  val tru = AST.LConst (Literal.trueLit, Basis.boolTy)
  val fls = AST.LConst (Literal.falseLit, Basis.boolTy)
  val u   = AST.LConst (Literal.unitLit, Basis.unitTy)

(* mkCase is fragile with respect to types...i.e., no typechecking. *)
(* If you feed it nonsense, it will produce nonsense. *)
  fun mkCase (ps: AST.pat list) : AST.exp = 
    (case ps
       of [] => raise Fail "empty pat/exp list argument"
	| p::_ => let
            val t = TypeOf.pat p
            val x = Var.new ("_fresh", t)
            fun m p = AST.PatMatch (p, zro)
            in
              AST.CaseExp (ASTUtil.mkVarExp (x, []), 
			   List.map m ps, 
			   Basis.intTy) 
            end
     (* end case *))

fun pairTy (t, u) = Types.TupleTy [t, u]

(* made-up datatypes for testing purposes *)

(* datatype tester = A of int | B of bool * int | C *)
  val testerCon = TyCon.newDataTyc (Atom.atom "tester", [])
  val testerTy  = Types.ConTy ([], testerCon)
  val testerA   = DataCon.new testerCon (Atom.atom "A", SOME Basis.intTy)
  val testerB   = DataCon.new testerCon (Atom.atom "B", 
					 SOME (pairTy (Basis.boolTy, Basis.intTy)))
  val testerC   = DataCon.new testerCon (Atom.atom "C", NONE)

(* datatype int_stack = E | S of int * int_stack *)
  val intStackCon = TyCon.newDataTyc (Atom.atom "int_stack", [])
  val intStackTy  = Types.ConTy ([], intStackCon)
  val intStackE   = DataCon.new intStackCon (Atom.atom "E", NONE)
  val intStackS   = DataCon.new intStackCon (Atom.atom "S", 
					     SOME (pairTy (Basis.intTy, intStackTy)))

  fun matchesOf (AST.CaseExp (_, ms, _)) = ms
    | matchesOf (AST.LetExp (AST.FunBind [AST.FB (_, _, b)], _)) = matchesOf b
    | matchesOf _ = raise Fail "todo: matchesOf, a hacked-together convenience function in the test framework"

  fun println s = (TextIO.print s; TextIO.print "\n")

  fun testExpU' (e: AST.exp) : unit = let
    val p = MatchCheck.mkPatMat (matchesOf e)
    val _ = println (patmat p)
    in
       println "\nTesting...";
       MatchCheck.checkExpInternal (Error.mkErrStream "/var/tmp/bogus-file", e);
       println "done."
    end

  fun testExpU expectingSuccess e = 
    (TextIO.print "***** expecting ";
     println (if expectingSuccess then "SUCCESS:" else "FAILURE:");
     testExpU' e;
     println "")

  fun testExpI' (e: AST.exp) : unit = let
    val p = MatchCheck.mkPatMat (matchesOf e)
    val _ = println (patmat p)
    fun pstos ps = String.concatWith "," (List.map MatchCheck.patToString ps)
    in
       println "\nTesting...";
       MatchCheck.checkExpInternal (Error.mkErrStream "/var/tmp/bogus-file", e);
       println "Done."
    end

  fun testExpI expectingSuccess e = 
    (TextIO.print "***** expecting ";
     println (if expectingSuccess then "SUCCESS:" else "FAILURE:");
     testExpI' e;
     println "")

  val testExp = testExpI

  fun test 0 = let
        val e = mkCase [AST.WildPat Basis.boolTy]
        in
          testExp true e
        end
    | test 1 = let
        val e = mkCase [AST.ConstPat tru]
        in
          testExp false e
        end
    | test 2 = let
        val e = mkCase [AST.ConstPat u]
        in
          testExp true e
        end 
    | test 3 = let
	val e = mkCase [AST.WildPat Basis.unitTy]
        in
          testExp true e
        end
    | test 4 = let
        val e = mkCase [AST.VarPat (Var.new ("y", Basis.unitTy))]
        in
          testExp true e
        end
    | test 5 = let
        val e = mkCase [AST.ConstPat tru, AST.ConstPat fls]
        in
          testExp true e
        end
    | test 6 = let
        val e = mkCase [AST.TuplePat [AST.ConstPat tru, AST.ConstPat tru],
			AST.WildPat (Types.TupleTy [Basis.boolTy, Basis.boolTy])]
        in
          testExp true e
        end
    | test 7 = let
        val e = mkCase [AST.TuplePat [AST.ConstPat tru, AST.ConstPat tru],
			AST.TuplePat [AST.ConstPat fls, AST.ConstPat fls]]
        in
	  testExp false e
        end
    | test 8 = let
        val e = mkCase [AST.TuplePat [AST.ConstPat tru, AST.ConstPat u],
			AST.TuplePat [AST.ConstPat fls, AST.ConstPat u]]
        in
	  testExp true e
        end
    | test 9 = let
        val e = mkCase [AST.WildPat testerTy]
        in
          testExp true e
        end
    | test 10 = let
        val e = mkCase [AST.WildPat testerTy, 
			AST.WildPat testerTy]
        in
          testExp false e
        end
    | test 11 = let
        val e = mkCase [AST.VarPat (Var.new ("x", testerTy)), 
			AST.WildPat testerTy]
        in
          testExp false e
        end
    | test 12 = let
        val e = mkCase [AST.ConstPat (AST.DConst (testerC, [])),
			AST.WildPat testerTy]
        in
	  testExp true e
        end
    | test 13 = let
        val e = 
          mkCase [AST.ConstPat (AST.DConst (testerC, [])),
		  AST.ConPat (testerA, [], AST.WildPat Basis.intTy),
		  AST.ConPat (testerB, [], AST.WildPat (pairTy (Basis.boolTy, Basis.intTy)))]
        in
	  testExp true e
        end
    | test 14 = let
        val e =
          mkCase [AST.ConstPat (AST.DConst (testerC, [])),
		  AST.ConPat (testerA, [], AST.WildPat Basis.intTy),
		  AST.ConPat (testerB, [], AST.WildPat (pairTy (Basis.boolTy, Basis.intTy))),
		  AST.WildPat testerTy]
        in
	  testExp false e
        end
    | test 15 = let
        val e =
          mkCase [AST.TuplePat [AST.ConstPat tru, 
				AST.ConstPat (AST.DConst (testerC, []))],
		  AST.TuplePat [AST.ConstPat fls,
				AST.WildPat testerTy]]
        in
	  testExp false e
        end
    | test 16 = let
        val e =
          mkCase [AST.TuplePat [AST.ConstPat tru, 
				AST.ConstPat (AST.DConst (testerC, []))],
		  AST.TuplePat [AST.ConstPat fls,
				AST.WildPat testerTy],
		  AST.WildPat (pairTy (Basis.boolTy, testerTy))]
        in
	  testExp true e
        end
    | test 17 = let
        val m = Var.new ("m", Basis.intTy)
        val n = Var.new ("n", Basis.intTy)
        val e =
	  mkCase [AST.ConPat (testerA, [], AST.VarPat m),
		  AST.ConPat (testerB, [], AST.TuplePat [AST.ConstPat tru,
							 AST.VarPat n]),
		  AST.ConPat (testerB, [], AST.WildPat (pairTy (Basis.boolTy, 
								Basis.intTy))),
		  AST.ConstPat (AST.DConst (testerC, []))]
        in
	  testExp true e
        end
    | test 18 = let
        val tt = AST.ConstPat tru
	val ff = AST.ConstPat fls
	val ww = AST.WildPat Basis.boolTy
        val e = mkCase [AST.TuplePat [tt, tt, tt],
			AST.TuplePat [tt, tt, ww],
			AST.TuplePat [ww, ww, ff]]
        in
          testExp false e
        end
    | test 19 = let
        val tt = AST.ConstPat tru
	val ff = AST.ConstPat fls
	val ww = AST.WildPat Basis.boolTy
        val e = mkCase [AST.TuplePat [tt, tt, tt],
			AST.TuplePat [tt, tt, ww],
			AST.TuplePat [ww, ww, ff],
			AST.TuplePat [ff, ff, ww]]
        in
          testExp false e
        end
    | test 20 = let
        val tt = AST.ConstPat tru
	val ff = AST.ConstPat fls
	val ww = AST.WildPat Basis.boolTy
	val e = mkCase [AST.TuplePat [tt, tt, ww],
			AST.TuplePat [tt, ff, ww],
			AST.TuplePat [ff, tt, ww],
			AST.TuplePat [ww, ww, tt],
			AST.TuplePat [ww, ww, ff]]
        in
          testExp true e
        end
    | test 21 = let
        val k0 = ASTUtil.mkIntConst 0
	val k1 = ASTUtil.mkIntConst 1
        val e = mkCase [AST.ConstPat k0,
			AST.ConstPat k1]
        in
          testExp false e
        end
    | test 22 = let
        val k0 = ASTUtil.mkIntConst 0
	val k1 = ASTUtil.mkIntConst 1
        val e = mkCase [AST.ConstPat k0,
			AST.WildPat Basis.intTy,
			AST.ConstPat k1]
        in
          testExp false e
        end
    | test 23 = let
        val k0 = ASTUtil.mkIntConst 0
	val k1 = ASTUtil.mkIntConst 1
        val e = mkCase [AST.ConstPat k0,
			AST.ConstPat k1,
			AST.WildPat Basis.intTy]
        in
	  testExp true e
        end
    | test 24 = let
        val kE = AST.ConstPat (AST.DConst (intStackE, []))
        val w  = AST.WildPat Basis.intTy
        val s  = (fn ps => AST.ConPat (intStackS, [], AST.TuplePat ps))
        val e = mkCase [kE,
			s [w, kE],
			s [w, s [w, kE]]]
        in
          testExp false e
        end					       
    | test 25 = let
        val kE = AST.ConstPat (AST.DConst (intStackE, []))
        val w  = AST.WildPat Basis.intTy
        val s  = (fn ps => AST.ConPat (intStackS, [], AST.TuplePat ps))
        val e = mkCase [kE,
			s [w, kE],
			s [w, s [w, kE]],
			AST.WildPat intStackTy]
        in
	  testExp true e
        end
    | test 26 = let
	val wb = AST.WildPat Basis.boolTy
        val e = mkCase [AST.TuplePat [wb, AST.TuplePat [wb, wb]]]
        in
          testExp true e
        end
    | test 27 = let
        val wb = AST.WildPat Basis.boolTy
        val e = mkCase [AST.TuplePat [wb, AST.TuplePat [wb, AST.ConstPat tru]]]
        in
	  testExp false e
        end
    | test 28 = let
        val tup = AST.TuplePat
        val wb = AST.WildPat Basis.boolTy
	val e = mkCase [tup [wb, tup [wb, AST.ConstPat tru]],
			tup [AST.ConstPat tru, tup [wb, wb]]]
        in
	  testExp false e
        end
    | test 29 = let
        val tup = AST.TuplePat
        val wb = AST.WildPat Basis.boolTy
	val e = mkCase [tup [wb, tup [wb, AST.ConstPat tru]],
			tup [AST.ConstPat tru, tup [wb, wb]],
			tup [AST.ConstPat fls, tup [wb, AST.ConstPat fls]]]
        in
	  testExp true e
        end
    | test 30 = let
        val e = mkCase [AST.ConstPat (AST.LConst (Literal.String "foo", Basis.stringTy))]
        in
          testExp false e
        end
    | test 31 = let
        val e = mkCase [AST.ConstPat (AST.LConst (Literal.String "foo", Basis.stringTy)),
			AST.WildPat Basis.stringTy]
        in
          testExp true e
        end
    | test 32 = let
        val tup = AST.TuplePat
        val pt = AST.ConstPat tru
	val pf = AST.ConstPat fls
        val e = mkCase [tup [tup [pt, pt], tup [pt, pt]],
			tup [tup [pt, pt], tup [pt, pf]],
			tup [tup [pt, pt], tup [pf, pt]]]
        in
          testExp false e
        end
    | test 33 = let
        val e = mkCase [AST.TuplePat [AST.ConstPat tru, AST.ConstPat tru]]
        in
	  testExp false e
        end
    | test 34 = let
        val e = mkCase [AST.ConstPat u]
        in
	  testExp true e
        end
    | test 35 = let
        val e = mkCase [AST.TuplePat []]
        in
          testExp true e
        end
    | test 36 = let
        (* simulating the regression test dt-bug.pml, which match check doesn't catch *)
	val intPair = pairTy (Basis.intTy, Basis.intTy)
        val sphereCon = TyCon.newDataTyc (Atom.atom "sphere", [])
        val sphereTy = Types.ConTy ([], sphereCon)
	val sSphere = DataCon.new sphereCon (Atom.atom "Sphere", 
					     SOME intPair)
	val sPt1 = DataCon.new sphereCon (Atom.atom "Pt1", 
					  SOME Basis.intTy)
	val sTheVoid = DataCon.new sphereCon (Atom.atom "TheVoid",
					      NONE)
        val f = Var.new ("f", Types.FunTy (sphereTy, Basis.intTy))
	val x = Var.new ("s", sphereTy)
	val p = AST.ConPat (sSphere, [], AST.WildPat intPair)
        val b = AST.CaseExp (AST.VarExp (x, []),
			     [AST.PatMatch (p, ASTUtil.mkInt 0)],
			     Basis.intTy)
	val fbind = AST.FunBind [AST.FB (f, x, b)]
	val e = AST.LetExp (fbind, ASTUtil.mkInt 0)				     
        in
          testExp false e
        end
    | test n = raise Fail ("***** no such test: " ^ Int.toString n)

  fun testAll () = let
    fun lp k = (test k; lp (k+1))
	        handle Fail msg => println (msg ^ "\nHalting.")
    in
      lp 0
    end

end
