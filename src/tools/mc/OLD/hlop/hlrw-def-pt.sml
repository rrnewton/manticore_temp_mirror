(* hlrw-def-pt.sml
 *
 * COPYRIGHT (c) 2007 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 *)

structure HLRWDefPT = struct

     datatype raw_ty = datatype BOMTyPT.raw_ty

     datatype ty = datatype BOMTyPT.ty

     datatype pattern = Call of Atom.atom * pattern list
                      | Const of (Literal.literal * ty)
                      | Var of Atom.atom

     datatype rewrite = Rewrite of { label  : Atom.atom,
                                     lhs    : pattern,
                                     rhs    : pattern,
                                     weight : IntInf.int }

     datatype defn = RewriteDef of rewrite
                   | TypeDef of Atom.atom * ty

     type file = defn list

end (* HLRWDefPT *)
