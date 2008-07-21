(* std-env.sml
 *
 * COPYRIGHT (c) 2007 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 *
 * Mapping from AST types and variables to their BOL representations.
 *
 *)

structure BOMBasisEnv : sig

    val bindingEnv : BindingEnv.bom_env

  (* find the predefined type (for use in inline BOM) *)
    val getTy : ProgramParseTree.Var.var -> BOM.ty option
(*    val translateEnv : TranslateEnv.env*)

  end = struct

    structure B = Basis
    structure BTy = BOMTy
    structure BEnv = BindingEnv
    structure Var = ProgramParseTree.Var

    fun wrapTy rty = BOMTyUtil.wrap(BTy.T_Raw rty)

    val types = [
	    (B.boolTyc,		BTy.K_UNBOXED,	BTy.boolTy),
	    (B.intTyc,		BTy.K_BOXED,	wrapTy BTy.T_Int),
	    (B.longTyc,		BTy.K_BOXED,	wrapTy BTy.T_Long),
	    (B.floatTyc,	BTy.K_BOXED,	wrapTy BTy.T_Float),
	    (B.doubleTyc,	BTy.K_BOXED,	wrapTy BTy.T_Double),
	    (B.stringTyc,	BTy.K_BOXED,	BOMBasis.stringTy),
	    (B.listTyc,		BTy.K_UNIFORM,	BOMBasis.listTy),
	    (B.optionTyc,	BTy.K_UNIFORM,	BOMBasis.optionTy),
	    (B.exnTyc,		BTy.K_BOXED,	BTy.exnTy),
	    (B.threadIdTyc,	BOMTyUtil.kindOf(BTy.tidTy), BTy.tidTy),
	    (B.parrayTyc,       BTy.K_BOXED,	BOMBasis.ropeTy),
            (B.ivarTyc,         BTy.K_BOXED,   BOMBasis.ivarTy),
(*
	    (B.mvarTyc, ),
*)
	    (B.eventTyc,	BTy.K_BOXED,	BOMBasis.evtTy),
	    (B.chanTyc,		BTy.K_BOXED,	BOMBasis.chanTy),
	  (* internal types *)
(*	    (F.futureTyc,       BTy.K_BOXED,	BTy.futureTy),*)
(*	    (R.ropeTyc,         BTy.K_BOXED,	BOMBasis.ropeTy),*)
          (* arrays *)
	    (B.arrayTyc,        BTy.K_BOXED,    BTy.T_Any)
	  ]

    local 
    val bomTypes' = [
	("exn", BTy.exnTy)
    ]
    fun f (id, ty) = (id, Var.new("exn", ()), ty)
    val bomTypes = List.map f bomTypes'

  (* type bindings for translation *)
    val {
           getFn=getTy : ProgramParseTree.Var.var -> BOM.ty option, 
	   setFn=setTy : (ProgramParseTree.Var.var * BOM.ty option) -> unit, ...
        } = 
	   ProgramParseTree.Var.newProp (fn _ => NONE)

  (* seed the binding and module environments at once *)
    fun seed ((id, v, ty), varEnv) = (
print (Var.toString v^"\n");
	setTy(v, SOME ty);
	AtomMap.insert(varEnv, Atom.atom id, v))
    val tyEnv = List.foldl seed AtomMap.empty bomTypes
    in
    val getTy = getTy
    val bindingEnv = BEnv.BOMEnv {
		       varEnv=AtomMap.empty,
		       hlopEnv=AtomMap.empty,
		       tyEnv=tyEnv
		     }
    end

  end (* BOMBasisEnv *)
