(* parray.pml
 *
 * COPYRIGHT (c) 2009 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 *
 * Parallel array utilities.
 *)

structure PArray = struct

  fun failwith s = raise Fail s

  _primcode (
    define inline @to-rope (x : parray / _ : exh) : Rope.rope =
      return ((Rope.rope)x);
    define inline @from-rope (x : Rope.rope / _ : exh) : parray =
      return ((parray)x);
    )

  type 'a parray = 'a parray

  (* I would prefer these were local but I had to expose them to the compiler for the FT. *)
  val toRope : 'a parray -> 'a Rope.rope = _prim(@to-rope)
  val fromRope : 'a Rope.rope -> 'a parray = _prim(@from-rope)

  (* in *)

  (* Rope implementations are the default. *)
  (* These functions are swapped out when the FT is turned on. *)
  fun sub (pa, i) = Rope.sub (toRope pa, i)
  fun length pa = Rope.length (toRope pa)
  fun tab (n, f) = fromRope (Rope.tabulate (n, f))
  fun tabFromToStep (a, b, step, f) = fromRope (Rope.tabFromToStep (a, b, step, f))
  fun map f pa = fromRope (Rope.map f (toRope pa))
  fun reduce rator init pa = Rope.reduce rator init (toRope pa)
  fun segreduce (oper,init,pa) = let
(*    val b = Time.now() *)
    val res = map (reduce oper init) pa
(*    val e = Time.now()
    val _ = Print.printLn ("Time spent in PArray.segreduce: " ^ (Time.toStringMicrosec (e-b))) *)
    in
      res
    end
  fun mapSP (f, paa) = let
(*    val b = Time.now() *)
    val res = map (map f) paa
(*    val e = Time.now()
    val _ = Print.printLn ("Time spent in PArray.mapSP: " ^ (Time.toStringMicrosec (e-b))) *)
    in
      res
    end
  fun range (from, to_, step) = fromRope (Rope.range (from, to_, step))
  fun app f pa = Rope.app f (toRope pa)

(* These higher-dimension regular tabs (tab2D, etc.) are spelled out since I 
 * want them to be relatively fast for fair comparisons with flattened versions. 
 *)
  fun tab2D ((iFrom, iTo, iStep), (jFrom, jTo, jStep), f) = 
    tabFromToStep (iFrom, iTo, iStep, fn i => 
      tabFromToStep (jFrom, jTo, jStep, fn j => f (i, j)))

  fun tab3D ((iF, iT, iS), (jF, jT, jS), (kF, kT, kS), f) = 
    tabFromToStep (iF, iT, iS, fn i => 
      tabFromToStep (jF, jT, jS, fn j =>
        tabFromToStep (kF, kT, kS, fn k => f (i, j, k))))

  fun tab4D ((iF, iT, iS), (jF, jT, jS), (kF, kT, kS), (lF, lT, lS), f) = 
    tabFromToStep (iF, iT, iS, fn i => 
      tabFromToStep (jF, jT, jS, fn j =>
        tabFromToStep (kF, kT, kS, fn k => 
          tabFromToStep (lF, lT, lS, fn l => f (i, j, k, l)))))

  fun tab5D ((iF, iT, iS), (jF, jT, jS), (kF, kT, kS), (lF, lT, lS), (mF, mT, mS), f) = 
    tabFromToStep (iF, iT, iS, fn i => 
      tabFromToStep (jF, jT, jS, fn j =>
        tabFromToStep (kF, kT, kS, fn k => 
          tabFromToStep (lF, lT, lS, fn l => 
            tabFromToStep (mF, mT, mS, fn m => f (i, j, k, l, m))))))

(* higher dimensional regular tabbing *)
  fun tabHD (triples, f) = failwith "tabHD-todo"

  (* fun filter (pred, pa) = fromRope(Rope.filter pred (toRope pa)) *)
  (* fun rev pa = fromRope(Rope.rev(toRope pa)) *)
  (* fun fromList l = fromRope(Rope.fromList l) *)
  fun concat (pa1, pa2) = fromRope(Rope.concat(toRope pa1, toRope pa2))
  (* fun tabulateWithPred (n, f) = fromRope(Rope.tabulate(n, f)) *)
  (* fun forP (n, f) = Rope.for (n,f) *)
  (* fun repP (n, x) = fromRope(Rope.tabulate (n, fn _ => x)) *)

  (* end (* local *) *)

 (* I can't write polymorphic toString, unfortunately. Specific implementations below. *)
  (* toString : ('a -> string ) -> string -> 'a parray -> string *)
  (* FIXME: should we exploit the fact that we're dealing with a rope? *)
    fun toString eltToString sep parr = let
	  val n = length parr
	  fun lp (m, acc) = if (m >= n)
		then List.rev ("|]" :: acc)
		else let
		  val s = eltToString (sub (parr, m))
		  in
		    if (m = (n-1)) then
		      List.rev ("|]" :: s :: acc)
		    else
		      lp (m+1, sep :: s :: acc)
		  end
	  val init = "[|" :: nil
	  in
	    String.concat (lp (0, init))
	  end

  fun tos_int (parr : int parray) = let
    fun tos i = Int.toString (parr ! i)
    fun lp (i, acc) =
      if (i<0) then
        String.concat ("[|"::acc)
      else
        lp (i-1, tos(i)::","::acc)
    val n = length parr
    in
      if (n<0) then
        failwith "tos_int - BUG: negative length"
      else if (n=0) then 
        "[||]"
      else let
        val init = [tos(n-1),"|]"]
        in
          lp (n-2, init)
        end
    end

  fun tos_intParr (parr : int parray parray) = let
    fun tos i = tos_int (parr ! i)
    fun lp (i, acc) = 
      if (i<0) then
        String.concat ("[|"::acc)
      else
        lp (i-1, tos(i)::",\n"::acc)
    val n = length parr
    in
      if (n<0) then
        failwith "tos_intParr - BUG: negative length"
      else if (n=0) then
        "[||]"
      else let
        val init = [tos(n-1), "\n|]"]
        in
          lp (n-2, init)
        end
    end

  fun tos_intParrParr (parr : int parray parray parray) = let
    fun tos i = tos_intParr (parr ! i)
    fun lp (i, acc) = 
      if (i<0) then
        String.concat ("[|"::acc)
      else
        lp (i-1, tos(i)::",\n"::acc)
    val n = length parr
    in
      if (n<0) then
        failwith "tos_intParrParr - BUG: negative length"
      else if (n=0) then
        "[||]"
      else let
        val init = [tos(n-1), "\n|]"]
        in
          lp (n-2, init)
        end
    end

  fun tos_intPair parr = let
    val itos = Int.toString
    fun tos i = let
      val (m,n) = parr!i 
      in
        "(" ^ itos m ^ "," ^ itos n ^ ")"
      end
    fun lp (i, acc) =
      if (i<0) then
        String.concat ("[|"::acc)
      else
        lp (i-1, tos(i)::","::acc)
    val n = length parr
    in
      if (n<0) then
        failwith "tos_intPair - BUG: negative length"
      else if (n=0) then "[||]"
      else let
        val init = [tos(n-1),"|]"]
        in
          lp (n-2, init)
        end
    end

  fun tos_float (parr : float parray) = let
    fun tos i = Float.toString (parr ! i)
    fun lp (i, acc) =
      if (i<0) then
        String.concat ("[|"::acc)
      else
        lp (i-1, tos(i)::","::acc)
    val n = length parr
    in
      if (n<0) then
        failwith "tos_float - BUG: negative length"
      else if (n=0) then 
        "[||]"
      else let
        val init = [tos(n-1),"|]"]
        in
          lp (n-2, init)
        end
    end

  fun tos_dbl (parr : double parray) = let
    fun tos i = Double.toString (parr ! i)
    fun lp (i, acc) =
      if (i<0) then
        String.concat ("[|"::acc)
      else
        lp (i-1, tos(i)::","::acc)
    val n = length parr
    in
      if (n<0) then
        failwith "tos_int - BUG: negative length"
      else if (n=0) then 
        "[||]"
      else let
        val init = [tos(n-1),"|]"]
        in
          lp (n-2, init)
        end
    end

  fun tos_dblParr (parr : double parray parray) = let
    fun tos i = tos_dbl (parr ! i)
    fun lp (i, acc) = 
      if (i<0) then
        String.concat ("[|"::acc)
      else
        lp (i-1, tos(i)::",\n"::acc)
    val n = length parr
    in
      if (n<0) then
        failwith "tos_intParr - BUG: negative length"
      else if (n=0) then
        "[||]"
      else let
        val init = [tos(n-1), "\n|]"]
        in
          lp (n-2, init)
        end
    end

end

 val concatP = PArray.concat
 val reduceP = PArray.reduce 

(* (\* FIXME: the following definitions should be in a separate *)
(*  * file (a la sequential/pervasives.pml) *)
(*  *\) *)
(* (\* Below is the subset of the parallel array module that should bound at the top level. *\) *)

(* val filterP = PArray.filter *)
(* val subP = PArray.sub *)
(* val revP = PArray.rev *)
(* val lengthP = PArray.length *)
(* val mapP = PArray.map *)
(* val fromListP = PArray.fromList *)

(* val tabP = PArray.tabulateWithPred *)
(* val forP = PArray.forP *)
(* *\) *)
