(* array.pml
 *
 * COPYRIGHT (c) 2008 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 *
 * Mutable arrays.
 *)

#define DATA_OFF        0
#define LENGTH_OFF      1

structure Array64 =
  struct

    structure PT = PrimTypes

    _primcode (

      typedef array = PT.array;

      extern void* M_NewArray (void*, int, void*);
 
    (* allocate and initialize an array *)
      define @array (n : int, elt : any / exh : exh) : array =
        let elt : any = (any)elt
        let elt : any = promote(elt)
      (* obtain the data chunk from the C runtime *)
        let data : any = ccall M_NewArray(host_vproc, n, elt)
        let arr : array = alloc(data, n)
        return(arr)
      ;

      define @length (arr : array / exh : exh) : int =
	return(SELECT(LENGTH_OFF, arr))
      ;

      define @update (arr : array, i : int, x : any / exh : exh) : () =
	do assert(I32Gte(i,0))
	let len : int = @length(arr / exh)
	do assert(I32Lt(i,len))
        let data : any = SELECT(DATA_OFF, arr)
       (* since the array is in the global heap, x must also be in the global heap *)
	let x : any = (any)x
	let x : any = promote(x)
	let x : PT.bool  = ArrayStoreI64(data, i, x)
	return()
      ;

      define @sub (arr : array, i : int / exh : exh) : any =
	let len : int = @length(arr / exh)
	do assert(I32Gte(i,0))
	do assert(I32Lt(i,len))
        let data : any = SELECT(DATA_OFF, arr)
	let x : any = ArrayLoadI64(data, i)
	return(x)
      ;

      define @array-w (arg : [PT.ml_int, any] / exh : exh) : array =
	@array(#0(#0(arg)), #1(arg) / exh)
      ;

      define @length-w (arr : array / exh : exh) : PT.ml_int =
	let len : int = @length(arr / exh)
	return(alloc(len))
      ;

      define @sub-w (arg : [array, PT.ml_int] / exh : exh) : any =
	@sub(#0(arg), #0(#1(arg)) / exh)
      ;

      define @update-w (arg : [array, PT.ml_int, any] / exh : exh) : PT.unit =
	do @update(#0(arg), #0(#1(arg)), #2(arg) / exh)
	return(UNIT)
      ;

    )

    type 'a array = _prim( PT.array )

    val array : int * 'a -> 'a array = _prim(@array-w)
    val length : 'a array -> int = _prim(@length-w)
    val sub : 'a array * int -> 'a = _prim(@sub-w)
    val update : 'a array * int * 'a -> unit = _prim(@update-w)

    fun tabulate (n, f : int -> 'a) = let
	  val a = array(n, f 0)
	  fun tab i =
	        if i < n 
		  then (update(a, i, f i);
			tab(i + 1))
		else a
          in
	    tab 1
	  end

    fun app f arr = let
	    val len = length arr
	    fun app i =
		if i < len then (f (sub (arr, i)); app (i + 1))
		else ()
	in
	    app 0
	end


  end
