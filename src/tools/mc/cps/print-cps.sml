(* print-cps.sml
 *
 * COPYRIGHT (c) 2007 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 *)

structure PrintCPS : sig

    val output : TextIO.outstream * CPS.module -> unit
    val print : CPS.module -> unit

  end = struct

    fun output (outS, CPS.MODULE{name, externs, body}) = let
	  fun pr s = TextIO.output(outS, s)
	  fun prl s = pr(String.concat s)
	  fun prIndent 0 = ()
	    | prIndent n = (pr "  "; prIndent(n-1))
	  fun indent i = prIndent i
	  fun prList' toS [] = ()
	    | prList' toS [x] = pr(toS x)
	    | prList' toS l = let
		fun prL [] = ()
		  | prL [x] = pr(toS x)
		  | prL (x::r) = (pr(toS x); pr ","; prL r)
		in
		  prL l
		end
	  fun prList toS [] = pr "()"
	    | prList toS [x] = pr(toS x)
	    | prList toS l = let
		fun prL [] = ()
		  | prL [x] = pr(toS x)
		  | prL (x::r) = (pr(toS x); pr ","; prL r)
		in
		  pr "("; prL l; pr ")"
		end
	  fun varBindToString x = String.concat[
		  CPS.Var.toString x, ":", CPSTyUtil.toString(CPS.Var.typeOf x)
		]
	  fun varUseToString x = CPS.Var.toString x
	  fun prExp (i, CPS.Exp(ppt, e)) = (
		indent i;
		case e
		 of CPS.Let([], rhs, e) => (
		      pr "do "; prRHS rhs; pr "\n";
		      prExp (i, e))
		  | CPS.Let(xs, rhs, e) => (
		      pr "let "; prList varBindToString xs; pr " = "; prRHS rhs; pr "\n";
		      prExp (i, e))
		  | CPS.Fun(fb::fbs, e) => (
		      prLambda(i, "fun ", fb);
		      List.app (fn fb => (indent i; prLambda(i, "and ", fb))) fbs;
		      prExp (i, e))
		  | CPS.Fun _ => raise Fail "empty function binding"
		  | CPS.Cont(fb, e) => (prLambda(i, "cont ", fb); prExp (i, e))
		  | CPS.If(cond, e1, e2) => prIf(i, cond, e1, e2)
		  | CPS.Switch(x, cases, dflt) => let
		      fun prCase (c, e) = (
			    indent (i+1);
			    prl ["case 0x", Word.toString c, ":\n"];
			    prExp (i+2, e))
		      in
			prl ["switch ", varUseToString x, "\n"];
			List.app prCase cases;
			case dflt
			 of NONE => ()
			  | SOME e => (indent(i+1); pr "default:\n"; prExp(i+2, e))
			(* end case *);
                        (indent (i+1); pr "end\n")
		      end
		  | CPS.Apply(f, args, rets) => (
		      prl["apply ", varUseToString f, " ("];
		      prList' varUseToString args;
		      pr " / ";
		      prList' varUseToString rets;
		      pr ")\n")
		  | CPS.Throw(k, args) => (
		      prl["throw ", varUseToString k, " "];
		      prList varUseToString args;
		      pr "\n")
		(* end case *))
	  and prRHS (CPS.Var ys) = prList varUseToString ys
	    | prRHS (CPS.Cast(ty, y)) = prl["(", CPSTyUtil.toString ty, ")", varUseToString y]
	    | prRHS (CPS.Const(lit, ty)) = prl[
		  Literal.toString lit, ":", CPSTyUtil.toString ty
		]
	    | prRHS (CPS.Select(i, y)) = prl ["#", Int.toString i, "(", varUseToString y, ")"]
	    | prRHS (CPS.Update(i, y, z)) = prl [
		  "#", Int.toString i, "(", varUseToString y, ") := ", varUseToString z
		]
	    | prRHS (CPS.AddrOf(i, y)) = prl ["&", Int.toString i, "(", varUseToString y, ")"]
	    | prRHS (CPS.Alloc(ty, ys)) = let
		val mut = (case ty of CPSTy.T_Tuple(true, _) => "!" | _ => "")
		in
		  pr(concat["alloc ", mut, "("]); prList' varUseToString ys; pr ")"
		end
	    | prRHS (CPS.Promote y) = prl["promote(", varUseToString y, ")"]
	    | prRHS (CPS.Prim p) = pr (PrimUtil.fmt varUseToString p)
	    | prRHS (CPS.CCall(f, args)) = (
		prl ["ccall ", varUseToString f, " "];
		prList varUseToString args)
	    | prRHS (CPS.HostVProc) = pr "host_vproc()"
	    | prRHS (CPS.VPLoad(offset, vp)) = prl [
		  "vpload(", varUseToString vp, "+", IntInf.toString offset, ")"
		]
	    | prRHS (CPS.VPStore(offset, vp, x)) = prl [
		  "vpstore(", varUseToString vp, "+", IntInf.toString offset, ",",
		  varUseToString x, ")"
		]
	    | prRHS (CPS.VPAddr(offset, vp)) = prl [
		  "vpaddr(", varUseToString vp, "+", IntInf.toString offset, ")"
		]
	  and prLambda (i, prefix, CPS.FB{f, params, rets, body}) = let
		fun prParams params = prList' varBindToString params
		in
		  prl [prefix, varUseToString f, " "];
		  pr "(";
		  case (params, rets)
		   of ([], []) => ()
		    | (_, []) => prParams params
		    | ([], _) => (pr "-; "; prParams rets)
		    | _ => (prParams params; pr " / "; prParams rets)
		  (* end case *);
		  pr ") =\n";
		  prExp (i+2, body)
		end
	  and prIf (i, cond, e1, CPS.Exp(_, CPS.If(cond', e2, e3))) = (
		prl ["if ", condToString cond, " then\n"];
		prExp(i+1, e1);
		indent (i); pr "else "; prIf(i, cond', e2, e3))
	    | prIf (i, cond, e1, e2) = (
		prl ["if ", condToString cond, " then\n"];
		prExp(i+1, e1);
		indent (i); pr "else\n"; prExp(i+1, e2))
	  and condToString cond = CondUtil.fmt varUseToString cond
	  fun prExtern cf = (indent 1; prl [CFunctions.cfunToString cf, "\n"])
	  in
	    prl ["(* CPS *)\nmodule ", Atom.toString name, "\n"];
	    List.app prExtern externs;
	    indent 1;
	    prLambda (1, "fun ", body)
	  end

    fun print m = output (TextIO.stdErr, m)

  end
