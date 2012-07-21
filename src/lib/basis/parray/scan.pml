(* scan.pml  
 *
 * COPYRIGHT (c) 2009 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 *
 * Follows the algorithms in Blelloch's "Prefix Sums and their Applications."
 * Adapted for ropes here.
 * (Nov 1990, CMS-CS-90-190)
 *
 * Follows the names of the operations given in Keller's thesis (pp. 53 ff).
 * currently it provides:
 * 
 * plusScan : num rope -> num rope ([1,1,1,1] => [1,2,3,4])
 * plusScan2 : num -> num rope -> num rope (2 [1,1,1,1] => [3,4,5,6])
 * prePlusScan : num rope -> num rope ([1,1,1,1] => [0,1,2,3])
 * prePlusScan2 : num -> num rope -> num rope ([2 [1,1,1,1] => [2,3,4,5])
 *
 * I write "num" here even though currently only int works.
 *)

structure Scan = struct

    structure S = Seq
    structure R = Rope

    datatype option = datatype Option.option

    type 'a seq = 'a S.seq

  (* We need a rope that can store a datum at every node. *)
  (* This is different from our other rope type. *)
  (* That datum will be an accumulator. *)
    datatype 'a scan_rope
      = Cat of ('a *      (* datum *)
		int *     (* depth *)
		int *     (* length *)
		'a scan_rope * (* left subtree *)
		'a scan_rope)  (* right subtree *)
      | Leaf of ('a *     (* datum *)
		 int *    (* length *)
		 'a seq)  (* data *)

  (* ***** UTILITIES ***** *)

  (* failwith : string -> 'a *)
  (* using this for the moment so we can observe the exception message at runtime *)
    fun failwith msg = (Print.printLn msg; (raise Fail msg))

  (* datumOf : 'a scan_rope -> 'a *)
  (* Select the accumulator out of a scan_rope node. *)
    fun datumOf x =
     (case x
        of (Cat (d, _, _, _, _)) => d
	 | (Leaf (d, _, _)) => d
       (* end case *))

  (* ***** FULL SCANS (as opp. to short-circuiting ***** *)

(*  
    fun seqscan seed seq =
      if S.null seq then (S.empty, seed)
      else let
        val len = S.length seq
        val seq' = S.tabulate (len, fn _ => seed)
        fun lp (i, last) = 
          if i >= len then (seq', last)
	  else let
            val _ = S.update (seq', i, last)
	    in
              lp (i+1, last + S.sub (seq, i))
	    end
        in
          lp (0, seed)
        end
*)

  (* seqscan : num -> num seq -> num seq * num *)
  (* Does a prefix scan starting from the given seed value. *)
  (* Returns the scanned sequence and the total. *)
  (* NOTE: this version more efficient with immutable vectors, since updates are costly *)
    fun seqscan seed seq =
	if S.null seq then (S.empty (), seed)
	else let
	    val len = S.length seq
          (* we accumulate the prefix, res, in reverse order *)
	    fun lp (i, last, res) =
		if i >= len then
		    (S.fromListRev res, last)
		else
		    lp (i+1, last + S.sub (seq, i), last :: res)
	    in
	      lp (0, seed, nil)
	    end

  (* seqsum : num -> num seq -> num *)
    fun seqsum seed s = let
      fun plus (a, b) = a + b
      in
        S.foldl plus seed s
      end

  (* upsweep : num -> num R.rope -> num scan_rope *)
    fun upsweep seed t = let
      fun lp r = 
       (case r 
	  of (R.Leaf s) => Leaf (seqsum seed s, S.length s, s)
	   | (R.Cat (d, len, rL, rR)) => let
               val (uL, uR) = (| lp rL, lp rR |)
               in 
                 Cat (datumOf uL + datumOf uR, d, len, uL, uR)
	       end)
      in
        lp t
      end   

  (* downsweep : num -> num scan_rope -> num rope *)
    fun downsweep seed t = let
      (* FIXME It seems odd that I'm underscoring the datums here... *)
      (* ...think about this more. *)
      fun lp (c, r) =
       (case r
          of (Cat (_, d, len, cL, cR)) => let
               val nL = datumOf cL
	       in
                 R.Cat (| d, len, lp (c, cL), lp (c+nL, cR) |)
               end
	   | (Leaf (_, len, s)) => let
               val (scanned, _) = seqscan c s
               in
                 R.Leaf scanned
               end)
      in
        lp (seed, t)
      end

  (* plusScan2 : num -> num rope -> num rope *)
  (* ex: plusScan2 2 [1,1,1,1] => [3,4,5,6] *)
    fun plusScan2 seed r =
      if R.isEmpty r then r
      else let
        val elt0 = R.sub (r, 0)
	val seed' = elt0 + seed
        in
          downsweep seed' (upsweep seed' r)
	end

  (* plusScan : num rope -> num rope *)
  (* ex: plusScan [1,1,1,1] => [1,2,3,4] *)
  (* nb: plusScan is equiv. to (plusScan2 0) *)
    fun plusScan r = plusScan2 0 r

  (* prePlusScan2 : num -> num rope -> num rope *)
  (* ex: prePlusScan2 2 [1,1,1,1] => [2,3,4,5] *)
    fun prePlusScan2 seed r = downsweep seed (upsweep seed r)

  (* prePlusScan : num rope -> num rope *)
  (* ex: prePlusScan [1,1,1,1] => plusScan [0,1,2,3] *)
  (* nb: prePlusScan is equiv to (prePlusScan2 0) *)
    fun prePlusScan r = downsweep 0 (upsweep 0 r)


(* for floats... *)
		     
  (* seqscan_float : num -> num seq -> num seq * num *)
  (* Does a prefix scan starting from the given seed value. *)
  (* Returns the scanned sequence and the total. *)
    fun seqscan_float (seed:float) seq =
      if S.null seq then (S.empty (), seed)
      else let
        val len = S.length seq
        val seq' = S.tabulate (len, fn _ => seed)
        fun lp (i, last) = 
          if i >= len then (seq', last)
	  else let
            val _ = S.update (seq', i, last)
	    in
              lp (i+1, last + S.sub (seq, i))
	    end
        in
          lp (0, seed)
        end

  (* seqsum_float : num -> num seq -> num *)
    fun seqsum_float (seed:float) s = let
      fun plus (a, b) = a + b
      in
        S.foldl plus seed s
      end

  (* upsweep_float : num -> num R.rope -> num scan_rope *)
    fun upsweep_float (seed:float) t = let
      fun lp r = 
       (case r 
	  of (R.Leaf s) => Leaf (seqsum_float seed s, S.length s, s)
	   | (R.Cat (d, len, rL, rR)) => let
               val (uL, uR) = (| lp rL, lp rR |)
               in 
                 Cat (datumOf uL + datumOf uR, d, len, uL, uR)
	       end)
      in
        lp t
      end   

  (* downsweep_float : num -> num scan_rope -> num rope *)
    fun downsweep_float (seed:float) t = let
      (* FIXME It seems odd that I'm underscoring the datums here... *)
      (* ...think about this more. *)
      fun lp (c, r) =
       (case r
          of (Cat (_, d, len, cL, cR)) => let
               val nL = datumOf cL
	       in
                 R.Cat (| d, len, lp (c, cL), lp (c+nL, cR) |)
               end
	   | (Leaf (_, len, s)) => let
               val (scanned, _) = seqscan_float c s
               in
                 R.Leaf scanned
               end)
      in
        lp (seed, t)
      end

  (* plusScan2_float : num -> num rope -> num rope *)
  (* ex: plusScan2_float 2 [1,1,1,1] => [3,4,5,6] *)
    fun plusScan2_float seed r =
      if R.isEmpty r then r
      else let
        val elt0 = R.sub (r, 0)
	val seed' = elt0 + seed
        in
          downsweep_float seed' (upsweep_float seed' r)
	end

  (* plusScan_float : num rope -> num rope *)
  (* ex: plusScan_float [1,1,1,1] => [1,2,3,4] *)
  (* nb: plusScan_float is equiv. to (plusScan2_float 0) *)
    fun plusScan_float r = plusScan2_float 0.0 r

end
