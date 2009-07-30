(* pquickhull.pml
 * 
 * Parallel quickhull written by Josh and Mike
 *) 

fun isLess c = (case c of LESS => true | _ => false)
fun isEqual c = (case c of EQUAL => true | _ => false)
fun isGreater c = (case c of GREATER => true | _ => false)

fun quicksort (cmp, xs) =
    if lengthP xs <= 1 then
	xs
    else
	let
	    val p = subP (xs, lengthP xs div 2)
	    val (lt, gt) = (| quicksort (cmp, filterP (fn x => isLess (cmp (x, p)), xs)), 
			      quicksort (cmp, filterP (fn x => isGreater (cmp (x, p)), xs)) |)
	in
	    concatP (lt, (concatP (filterP (fn x => isEqual (cmp (x, p)), xs), gt)))
	end

type point = float * float

fun samePoint ((x1, y1), (x2, y2)) = 
    (case (Float.compare (x1, x2), Float.compare (y1, y2))
      of (EQUAL, EQUAL) => true
       | _ => false)

fun distance ((q, w), (z, x)) = Float.sqrt ((q - z) * (q - z) + (w - x) * (w - x))

fun lastP x = subP (x, lengthP x - 1)

(* returns the point farthest from the line (a, b) in S *)
fun farthest (a, b, S) = 
    let
	fun dist x = (distance (a, x) + distance (b, x), x)
	fun cmp ((d1, _), (d2, _)) = Float.compare (d1, d2)
	val (_, pt) = lastP (quicksort (cmp, mapP (dist, S)))
    in
	pt
    end

(* returns true if the point p is to the right of the ray emanating from a and ending at b *)
fun isRight ((*a as *) (x1, y1), (* b as *) (x2, y2)) (* p as *) (x, y) = 
    (x1 - x) * (y2 - y) - (y1 - y) * (x2 - x) (* this quantity is the numerator of the 
					       * signed distance from the point p to the
					       * line (a,b). the sign represents the direction
					       * of the point w.r.t. the vector originating at
					       * a and pointing towards b. *)
    < 0.0

(* returns those points in S to the right of the ray emanating from a and ending at b *)
fun pointsRightOf (a : point, b : point, S : point parray) = filterP (isRight (a, b), S)


(* we maintain the invariant that the points a and b lie on the convex hull *)
fun quickhull' (a, b, S) = 
    if lengthP S = 0 then
	[| |]
    else
	let
	    val c = farthest (a, b, S)  (* c must also be on the convex hull *)
	in
	    concatP ([| c |], 
		     concatP (| quickhull' (a, c, pointsRightOf (a, c, S)), 
			        quickhull' (c, b, pointsRightOf (c, b, S)) |))
	end

(* takes a set of 2d points and returns the convex hull for those points *)	
fun quickhull S = 
    if lengthP S <= 1 then
	S
    else
	let
	    val p0 = subP (S, 0)
	    fun belowAndLeft ((x1, y1), (x2, y2)) = if x1 < x2 andalso y1 < y2 then (x1, y1) else (x2, y2)
	    fun aboveAndRight ((x1, y1), (x2, y2)) = if x1 > x2 andalso y1 > y2 then (x1, y1) else (x2, y2)
	    (* points x0 and y0 lie on the convex hull *)
	    val (x0, y0) = (| reduceP (belowAndLeft, p0, S), reduceP (aboveAndRight, p0, S) |)
	    (* remove x0 and y0 from S *)
	    val S = filterP (fn p => not (samePoint (p, x0) orelse samePoint (p, y0)), S)
	in
	    concatP ([| x0, y0 |], 
		     concatP (| quickhull' (x0, y0, pointsRightOf (x0, y0, S)),
		                quickhull' (y0, x0, pointsRightOf (y0, x0, S)) |))
	end
