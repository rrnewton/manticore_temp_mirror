(* vector.pml  
 *
 * COPYRIGHT (c) 2009 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 *
 *)

structure Vector = 
  struct

    _primcode (

      typedef vector = [ (* array data *) ![any], (* number of elements *) int ];

      extern void* AllocVector (void*, void*) __attribute__((alloc,pure));
      extern void* AllocVectorRev (void*, int, void*) __attribute__((alloc,pure));

      define inline @from-list (values : List.list / exh : exh) : vector =
	  let n : int = PrimList.@length (values / exh)
          let v : vector = AllocPolyVec (n, values)
	  return (v)
	;

      define @from-list-n (arg : [ml_int, list] / exh : exh) : vector = 
	  let n : int = #0(#0(arg))
          let values : list = #1(arg)
          let v : vector = AllocPolyVec (n, values)
	  return (v)
	;

      define inline @from-list-rev (arg : [List.list, ml_int] / exh : exh) : vector =
	  let vec : vector = ccall AllocVectorRev (host_vproc,  #0(#1(arg)), #0(arg))
	  return (vec)
	;

      define inline @length (vec : vector / exh : exh) : ml_int =
	  return (alloc(#1(vec)))
	;

      define inline @sub (arg : [vector, ml_int] / exh : exh) : any =
          let vec : vector = #0(arg)
          let i : int = #0(#1(arg))
	  do assert(I32Gte(i,0))
	  do assert(I32Lt(i,#1(vec)))
          let data : any = #0(vec)
          let x : any = ArrLoad(data, i)
	  return (x)
	;

    )

    type 'a vector = _prim (vector)

    val fromList : 'a list -> 'a vector = _prim (@from-list)
    val fromListN : int * 'a list -> 'a vector = _prim (@from-list-n)
  (* same as fromList, but expects that the list is in reverse order *)
    val fromListRev : 'a list * int -> 'a vector = _prim (@from-list-rev)
    val length : 'a vector -> int = _prim (@length)
    val sub : 'a vector * int -> 'a = _prim (@sub)

    fun app f v =
	let
	    val len = length v
	    fun lp i =
		if i < len then (f (sub (v, i)); lp (i + 1))
		else ()
	in
	    lp 0
	end

    fun tabulate (n, f) = fromList (List.tabulate (n, f))

    fun foldl f init vec = let
	val len = length vec
	fun fold (i, a) =
	    if i >= len then a else fold (i + 1, f (sub (vec, i), a))
    in
	fold (0, init)
    end

    fun foldr f init vec = let
	fun fold (i, a) =
	    if i < 0 then a else fold (i - 1, f (sub (vec, i), a))
    in
	fold (length vec - 1, init)
    end

    fun map f s = tabulate (length s, fn i => f (sub (s, i)))

  end
