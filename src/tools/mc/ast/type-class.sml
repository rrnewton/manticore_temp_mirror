(* type-class.sml
 *
 * COPYRIGHT (c) 2007 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 *
 * Utility functions for dealing with type classes.
 *)

structure TypeClass : sig

    val new : Types.ty_class -> Types.ty

    val toString : Types.ty_class -> string

  (* is a type in a type class (represented as a list of types)? *) 
    val isClass : Types.ty * Types.ty list -> bool

  (* is the type an equality type? Note this function accepts kinded meta
   * variables (unlike TypeUtil.eqType)
   *)
    val isEqualityType : Types.ty  -> bool

  end = struct

    structure Ty = Types

    fun new cl = Ty.MetaTy(Ty.MVar{info = ref(Ty.CLASS cl), stamp = Stamp.new()})

    fun toString Ty.Int = "INT"
      | toString Ty.Float = "FLOAT"
      | toString Ty.Num = "NUM"
      | toString Ty.Order = "ORDER"
      | toString Ty.Eq = "EQ"

    fun isClass (Ty.ConTy(_, tyc), c) =
	  List.exists (fn (Ty.ConTy(_, tyc')) => TyCon.same (tyc, tyc')) c
      | isClass _ = false

    fun isEqualityType Ty.ErrorTy = true
      | isEqualityType (Ty.MetaTy(Ty.MVar{info as ref(Ty.INSTANCE ty), ...})) = (
	  info := Ty.UNIV 0; (* blackhole *)
	  isEqualityType ty before info := Ty.INSTANCE ty)
      | isEqualityType (Ty.MetaTy(Ty.MVar{info as ref(Ty.CLASS _), ...})) =
	  true (* all classes are <= Eq *)
      | isEqualityType (Ty.ConTy(_, tyc)) = TyCon.isEqTyc tyc
      | isEqualityType (Ty.TupleTy tys) = List.all isEqualityType tys
      | isEqualityType _ = false

  end
