(*
 * This implementation of the memo table allows the underlying representation
 * to grow in chunks as more items are inserted.
 * The representation consists of a tuple with all of the administrative data
 * and a pointer to the top-level segment array.
 * The segment array starts with just one segment of the data, but will point
 * to each of the individual segments as the table grows. Addressing elements
 * is therefore based on the current size of the table and may require looking
 * down multiple buckets if the table has grown but the bucket has not yet been
 * rebalanced (i.e., the items moved up from prior locations).
 *
 *)

structure DynamicMemoTable =
  struct

  datatype 'a entry = UNINIT | INIT | ENTRY of long * int * 'a

  (* (growth, current elements, array of segments) *)
  type 'a table  = int Array.array * int Array.array * 'a entry Array.array option Array.array

  val maxSegments = 10000
  val threshold = 7 (* 7 = 70% *)
  val buckets = 2 
  val bucketSize = 200000
  val padding = 8
  val maxCollisions = 50000

  (* Larson's hash function constants *)
  val c = 314159:long
  val M = 1048583:long

  fun mkTable () = let
      val allSegments = Array.array (maxSegments, NONE)
      val firstSegment = Array.array (bucketSize * buckets, UNINIT)
      val _ = Array.update (allSegments, 0, SOME firstSegment)
  in
      (Array.array (1, 1),
       Array.tabulate (VProcUtils.numNodes() * padding, fn _ => 0),
       allSegments)
  end

  fun capacity i =
      case i
       of 0 => 0
        | n => (bucketSize * n)

  fun growIfNeeded (segments, itemCount, allSegments) = let
      val segmentCount = Array.sub (segments, 0)
  in
(*      if ((capacity (segmentCount) * buckets * 10 < (Array.sub (itemCount, VProcUtils.node() * padding) * threshold * (VProcUtils.numNodes()))) *)
      if ((maxCollisions < (Array.sub (itemCount, VProcUtils.node() * padding)))
          andalso segmentCount < maxSegments)
      then (let
               val segmentCount = segmentCount +1
	       val newSize = ((capacity segmentCount) - (capacity (segmentCount-1))) * buckets
               val new = Array.array (newSize, UNINIT)
               val _ = Array.update (allSegments, segmentCount-1, SOME new)
               fun clearCollisions i =
                   if i = ~1
                   then ()
                   else (Array.update (itemCount, i*padding, 0); clearCollisions (i-1))
               val _ = clearCollisions (VProcUtils.numNodes() - 1)  
               (* val _ = Array.update (itemCount, 0, 0)   *)
           in
               Array.update (segments, 0, segmentCount)
           end)
      else ()
  end

  (* returns the segment and segment-relative element index *) 
  fun findSegment i = let
      fun check (s,i) = 
          if (i >= capacity s)
          then check (s+1, i)
          else (s-1, (i - capacity (s-1)))
  in
      check (1, i)
  end

  (*
   * If the bucket is still in the UNINIT state, then this function will attempt to
   * probe the previous-capacity buckets for items that should now be at this location
   * and move them. If there are no such items, the bucket will transition to the INIT
   * state.
   * If this process encounters a bucket at the prior capacity that is also UNINIT,
   * this process needs to continue recursively.
   *)
  fun initBucket (segmentIndex, subIndex, hash, index, segmentCount, allSegments) = let
      val startIndex = subIndex * buckets
(*      val _ = print (String.concat[Int.toString segmentIndex, " subindex: ",
                                  Int.toString subIndex, " hash: ",
                                  Int.toString hash, " idnex: ",
                                  Int.toString index, "\n"])  *)
      val SOME(segment) = Array.sub (allSegments, segmentIndex)
  in
      case Array.sub (segment, startIndex)
       of UNINIT => (
	  if segmentCount = 1
	  then (Array.update (segment, startIndex, INIT))
	  else (let
	    val segmentCount' = segmentCount-1
		    val index' = hash mod (capacity segmentCount')
		    val (segmentIndex', subIndex') = findSegment index'                                        
               val _ = initBucket (segmentIndex', subIndex', hash, index', segmentCount', allSegments)
               val startIndex' = subIndex' * buckets
               val M' = capacity segmentCount'
               fun maybeMoveItems (i, next) = (
                   if (i = buckets)
                   then (Array.update (segment, startIndex, INIT))
                   else (let
                            val SOME(segment') = Array.sub (allSegments, segmentIndex')
                            val e = Array.sub (segment', startIndex' + i)
                        in
                            case e
                             of INIT => (Array.update (segment, startIndex+next, INIT))
                              (* BUG: Have to re-create the value because we don't support 'as'
                               *)
                              | ENTRY(t, key', value) => (
                                if (key' mod M' = index)
                                then (Array.update (segment, startIndex+next, ENTRY(t, key', value));
                                      maybeMoveItems (i+1, next+1))
                                else (maybeMoveItems (i+1, next)))
                              | UNINIT => (Array.update (segment, startIndex+next, INIT))
                        end))
           in
               maybeMoveItems (0, 0)
           end))
        | _ => () 
  end

  fun insert ((segments, itemCount, allSegments), key, item) = let
      val age = Time.now()
      val new = ENTRY (age, key, item)
      val key' = Int.toLong key
      val hash = (c * key') mod M 
      val hash = Long.toInt hash
      val segmentCount = Array.sub (segments, 0)
      val index = hash mod (capacity segmentCount)
      val (segmentIndex, subIndex) = findSegment index
      val _ = initBucket (segmentIndex, subIndex, hash, index, segmentCount, allSegments)

      val SOME(segment) = Array.sub (allSegments, segmentIndex)
      val startIndex = subIndex * buckets
(*      val node = VProcUtils.node() * padding
      val _ = Array.update (itemCount, node, Array.sub (itemCount, node) + 1)  *)
      val _ = growIfNeeded (segments, itemCount, allSegments)
      fun insertEntry (i, oldestTime, oldestOffset, overwrite) = (
          if i = buckets
          then (if overwrite
                then (let
                          val node = VProcUtils.node() * padding 
                      in
                          Array.update (itemCount, node, Array.sub (itemCount, node) + 1)
                      end)
                else ();
                Array.update (segment, startIndex + oldestOffset, new))
          else (case Array.sub (segment, startIndex + i)
                 of INIT => (Array.update (segment, startIndex + i, new))
                  | ENTRY (t, _, _) =>
                    if t < oldestTime
                    then insertEntry (i+1, t, i, overwrite)
                    else insertEntry (i+1, oldestTime, oldestOffset, true)
                  | UNINIT => (Array.update (segment, startIndex + i, new)
					    (*print (String.concat["INSERT-UNINIT: ", Int.toString segmentIndex,
						     " segment, ", Int.toString startIndex,
						     " startIndex, ", Int.toString i,
						     " i\n"]); raise Fail "insert encountered an uninitialized bucket"*)
			      )))
  in
      insertEntry (0, Int.toLong (Option.valOf Int.maxInt), 0, false)
  end

  fun find ((segments, itemCount, allSegments), key) = let
      val key' = Int.toLong key
      val hash = (c * key') mod M
      val hash = Long.toInt hash
      val segmentCount = Array.sub (segments, 0)
      val index = hash mod (capacity segmentCount)
      val (segmentIndex, subIndex) = findSegment index
      val _ = initBucket (segmentIndex, subIndex, hash, index, segmentCount, allSegments)
                         
      val SOME(segment) = Array.sub (allSegments, segmentIndex)
      val startIndex = subIndex * buckets
      fun findEntry (i) = (
          if (i = buckets)
          then NONE 
          else (let
                   val e = Array.sub (segment, startIndex + i)
               in
                   case e
                    of INIT => NONE
                     | ENTRY(_, key', value) =>
                       if key' = key
                       then (Array.update (segment, startIndex+i, ENTRY(Time.now(), key', value));
                             SOME value)
                       else (findEntry (i+1))
                     | UNINIT => (NONE
				      (*print (String.concat["FIND-UNINIT: ", Int.toString segmentIndex,
						     " segment, ", Int.toString startIndex,
						     " startIndex, ", Int.toString i,
						     " i\n"]); raise Fail "find encountered an uninitialized bucket"*))
               end))
  in
      findEntry 0 
  end

  end
