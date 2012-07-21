(* float-array.pml
 *
 * COPYRIGHT (c) 2011 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 *
 * Arrays of unboxed floats.
 *)

structure FloatArray = struct

structure U = UnsafeFloatArray

_primcode (
  typedef array = U.array;
  define inline @length (a : array / exh : exh) : ml_int =
    return(alloc(#1(a)))
  ;
)

type array = U.array

val length : array -> int = _prim (@length)

fun isIxInBounds (a, i) = i >= 0 andalso i < length a

fun update (a, i, x) = 
  if isIxInBounds (a, i) then
    U.update (a, i, x)
  else
    Debug.failwith ("FloatArray.update: index "^Int.toString i ^"out of bounds")
fun sub (a, i) =
  if isIxInBounds (a, i) then
    U.sub (a, i)
  else
    Debug.failwith ("FloatArray.sub: index "^Int.toString i ^"out of bounds")

fun tabulate (n, f) = 
  if n < 0 then
    raise Fail "Size"
  else let
    val a = U.create n
    fun lp i =
      if i < n then
	(U.update (a, i, f i); lp (i + 1))
      else
	()
    in
      lp 0;
      a
    end

fun array (n, init : float) = tabulate (n, fn _ => init)

fun modify f a = let
  val n = length a
  fun m i =
    if i < n then
      (update (a, i, f (sub (a, i))); m (i + 1))
    else
      ()
  in
    m 0
  end

fun app f a = let
  val len = length a
  fun app i = 
    if i < len then 
      (f (sub (a, i)); app (i + 1)) 
    else 
      ()
  in
    app 0
  end

end
