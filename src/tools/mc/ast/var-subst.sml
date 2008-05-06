(* var-subst.sml
 *
 * COPYRIGHT (c) 2007 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 *)

 (* : sig

    type subst

    val id        : subst
    val singleton : AST.var * AST.var -> subst 
    val add       : subst -> AST.var * AST.var -> subst 
    val pat       : subst -> AST.pat -> AST.pat
    val touchExp  : subst -> AST.exp -> AST.exp
    
    val subst1    : AST.var * AST.var * AST.exp -> AST.exp 

  end *)

structure VarSubst = 
  struct
  
    structure A = AST
    structure T = Types
    structure F = Futures
    
  (* fail : string -> 'a *)
    fun fail msg = raise Fail msg

  (* todo : string -> 'a *)
    fun todo thing = fail ("todo: " ^ thing)
			 
    structure VarMap = Var.Map

    type subst = Var.var VarMap.map

  (* id : subst *)
    val id : subst = VarMap.empty

  (* add : subst -> A.var * A.var -> subst *)
    fun add s (k, v) = VarMap.insert (s, k, v)

  (* singleton : A.var * A.var -> subst *)
    val singleton = add id

  (* pat : subst -> A.pat -> A.pat *)
    fun pat s p =
	let fun f (A.ConPat (c, ts, p)) = A.ConPat (c, ts, f p)
	      (*                                       ^^           *)
	      (* FIXME: I may need to futurize some of these types. *)
	      | f (A.TuplePat ps) = A.TuplePat (map f ps)
	      | f (v as A.VarPat x) = 
		    (case VarMap.find (s, x)
		       of NONE => v
			| SOME x' => A.VarPat x')
	      | f (A.WildPat t) = A.WildPat t
	      | f (k as A.ConstPat _) = k
	in
	    f p
	end

  (* expWalk : (A.var * A.ty list -> A.exp) -> subst -> A.exp -> A.exp *)
    fun expWalk f s e =
	let fun exp (A.LetExp (b, e)) = A.LetExp (binding b, exp e)
	      | exp (A.IfExp (e1, e2, e3, t)) =
		  A.IfExp (exp e1, exp e2, exp e3, t)
	      | exp (A.CaseExp (e, ms, t)) = A.CaseExp (exp e, map match ms, t)
	      | exp (A.HandleExp (e, ms, t)) = A.HandleExp (exp e, map match ms, t)
	      | exp (A.RaiseExp (e, t)) = A.RaiseExp (exp e, t)
	      | exp (A.FunExp (x, e, t)) = A.FunExp (x, exp e, t)
	      | exp (A.ApplyExp (e1, e2, t)) = A.ApplyExp (exp e1, exp e2, t)
	      | exp (m as A.VarArityOpExp _) = m
	      | exp (A.TupleExp es) = A.TupleExp (map exp es)
	      | exp (A.RangeExp (e1, e2, oe3, t)) =
		  A.RangeExp (exp e1, exp e2, Option.map exp oe3, t)
	      | exp (A.PTupleExp es) = A.PTupleExp (map exp es)
	      | exp (A.PArrayExp (es, t)) = A.PArrayExp (map exp es, t)
	      | exp (A.PCompExp (e, pes, opred)) = 
		  A.PCompExp (exp e, 
			      map (fn (p,e) => (pat s p, exp e)) pes,
			      Option.map exp opred)
	      | exp (A.PChoiceExp (es, t)) = A.PChoiceExp (map exp es, t)
	      | exp (A.SpawnExp e) = A.SpawnExp (exp e) 
	      | exp (k as A.ConstExp _) = k
	      | exp (v as A.VarExp (x, ts)) = f (x, ts)
	      | exp (A.SeqExp (e1, e2)) = A.SeqExp (exp e1, exp e2)
	      | exp (ov as A.OverloadExp _) = ov
	    and match (A.PatMatch (p, e)) = A.PatMatch (pat s p, exp e)
	      | match (A.CondMatch (p, cond, e)) = A.CondMatch (pat s p, exp cond, exp e)
	    and binding (A.ValBind (p, e)) = A.ValBind (pat s p, exp e)
	      | binding (A.PValBind (p, e)) = A.PValBind (pat s p, exp e)
	      | binding (A.DValBind (p, e)) = A.DValBind (pat s p, exp e)
	      | binding _ = todo "expWalk.binding"
	in
	    exp e
	end
	
  (* exp : subst -> A.exp -> A.exp *)
  (* Given a subst like [x -> y] and an expression (x + 2), *)
  (*   produces (y + 2). *)
    fun exp s =
	let fun f (x, ts) = (case VarMap.find (s, x)
			      of NONE => A.VarExp (x, ts)
			       | SOME x' => A.VarExp (x', ts))
	in
	    expWalk f s
	end

    fun exp' s e = let
        fun f (x, ts) = (case VarMap.find (s, x)
			      of NONE => A.VarExp (x, ts)
			       | SOME x' => e)
        in
	   expWalk f s
        end

  (* touchExp : subst -> A.exp * A.exp -> A.exp *)
  (* Given a subst like [x -> xf] and an expression (x + 2), *)
  (*   produces ((touch xf) + 2). *)
  (* n.b. Type-preserving when x : 'a and xf : 'a future. *)
    fun touchExp s =
	let fun f (x, ts) = (case VarMap.find (s, x)
				  of NONE => A.VarExp (x, ts)
				   | SOME x' => F.mkTouch (A.VarExp (x', ts)))
	in
	    expWalk f s
	end

  (* subst1 : A.var * A.var * A.exp -> A.exp *)
  (* Substitute one variable for another in an expression. *)
    fun subst1 (from, to, e) = exp (singleton (from, to)) e

  end
