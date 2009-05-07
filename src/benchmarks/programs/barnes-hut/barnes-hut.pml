(* barnes-hut.pml
 * 
 * Barnes Hut computation. This code is adapted from the Data-parallel
 * Haskell benchmark.
 * http://darcs.haskell.org/packages/ndp/examples/barnesHut/
 *) 

datatype bounding_box = BOX of (double * double * double * double)
datatype mass_point = MP of (double * double * double) (* xpos ypos mass *)
datatype particle = PARTICLE of (mass_point * double * double) (* mass point and velocity *)
datatype bh_tree 
  = BHT_QUAD of (double * double * double *     (* root mass point *)
		 bh_tree * bh_tree * bh_tree * bh_tree)
                                                (* subtrees *)
  | BHT_LEAF of (double * double * double *     (* root mass point *)
		 mass_point parray) 

fun log4 x = Int.ceilingLg x div 2

val epsilon : double = 0.05
val eClose : double = 0.01
val dt = 2.0

fun applyAccel (PARTICLE (mp, vx, vy), (ax, ay)) = PARTICLE (mp, vx+ax * dt, vy+ay * dt)

fun isClose (MP (x1, y1, m), x2, y2) = (x1-x2)*(x1-x2) + (y1-y2)*(y1-y2) < eClose

fun accel (MP (x1,  y1, _), x2, y2, m)  =
    let
	val dx   = x1 - x2 
	val dy   = y1 - y2 
	val rsqr = (dx * dx) + (dy * dy) 
	val r    = Double.sqrt rsqr 
    in
	if r < epsilon then
	    (0.0, 0.0) 
	else 
	    let
		val aabs = m / rsqr 
	    in
		(aabs * dx / r , aabs * dy / r) 
	    end
    end

(* the acceleration of a mass point after applying the force applied by surrounding
 * mass points
 *)
fun calcAccel (mpt, bht) = 
    (case bht
      of BHT_LEAF (x, y, m, _) =>
	 accel (mpt, x, y, m)
       | BHT_QUAD (x, y, m, st1, st2, st3, st4) =>
	 if isClose (mpt, x, y) then
	     let
		 val ((x1, y1), (x2, y2), (x3, y3), (x4, y4)) =
		     (| calcAccel (mpt, st1), 
		        calcAccel (mpt, st2), 
		        calcAccel (mpt, st3), 
		        calcAccel (mpt, st4) |)
	     in
		 (x1 + x2 + x3 + x4, y1 + y2 + y3 + y4)
	     end
	 else
	     accel (mpt, x, y, m)
    (* end case *))

fun calcCentroid (mpts : mass_point parray) : mass_point = 
    let
        fun circlePlus ((mx0,my0,m0), (mx1,my1,m1)) = (mx0+mx1, my0+my1, m0+m1)
	val (sum_mx, sum_my, sum_m) = 
	    reduceP (circlePlus, (0.0, 0.0, 0.0), [| (m*x, m*y, m) | MP (x, y, m) in mpts |])
    in
	MP (sum_mx / sum_m, sum_my / sum_m, sum_m)
    end

fun inBox (BOX (llx, lly, rux, ruy)) (MP (px, py, _)) =
    (px > llx) andalso (px <= rux) andalso (py > lly) andalso (py <= ruy)

(* split mass points according to their locations in the quadrants *)
fun buildTree (box, particles : mass_point parray) : bh_tree =
    let
	val maxDepth = log4 (lengthP particles) + 1
	fun build (depth, BOX (llx, lly, rux, ruy), particles) =
	    (* note that the stopping condition is based on the depth of our recursion tree. if we did not
	     * limit the depth, nontermination could occur when two or more particles lie on top of 
	     * each other. *)
	    (* in the worst case the depth of our tree is twice the depth of a perfectly balanced tree. *)
	    if lengthP particles <= 1 orelse depth >= maxDepth then
		let
		    val MP (x, y, m) = calcCentroid particles
		in
		    BHT_LEAF (x, y, m, particles)
		end
	    else
		let
		    val MP (x, y, m) = calcCentroid particles
		    val (midx,  midy) = ((llx + rux) / 2.0 , (lly + ruy) / 2.0) 
		    val b1 = BOX (llx,  lly,  midx,  midy)
		    val b2 = BOX (llx,  midy, midx,  ruy)
		    val b3 = BOX (midx, midy, rux,   ruy)
		    val b4 = BOX (midx, lly,  rux,   midy)
		    val depth' = depth + 1
		in
		    BHT_QUAD (| x, y, m, 
		                build (depth', b1, filterP (inBox b1, particles)),
		                build (depth', b2, filterP (inBox b2, particles)),
		                build (depth', b3, filterP (inBox b3, particles)),
		                build (depth', b4, filterP (inBox b4, particles)) |)
		end
    in
	build (0, box, particles)
    end

fun oneStep (pts : particle parray) : particle parray  =
    if lengthP pts = 0 then
	[| |]
    else
	let
	    val mspnts = [| mpnt | PARTICLE (mpnt, _, _) in pts |]
	    val MP (x0, y0, _) = subP (mspnts, 0)
	    (* the perimeter of this box fits snugly around the particles, but touches none of them *)
	    val box0 = BOX (| reduceP (Double.min, x0, [| x | MP (x, _, _) in mspnts |]) - epsilon,
			      reduceP (Double.min, y0, [| y | MP (_, y, _) in mspnts |]) - epsilon,
			      reduceP (Double.max, x0, [| x | MP (x, _, _) in mspnts |]) + epsilon,
			      reduceP (Double.max, y0, [| y | MP (_, y, _) in mspnts |]) + epsilon|)
	    val tree = buildTree (box0, mspnts)
	    val accels =  [| calcAccel (mspnt, tree) | mspnt in mspnts |]
 	in
	    [| applyAccel (pt, acc) | pt in pts, acc in accels |]
	end
