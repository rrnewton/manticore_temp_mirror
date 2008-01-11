val sqrt = sqrtd;
(*fun expt a = let fun expt' b = powd(a, b) in expt' end;*)
fun expt a = fail "todo";
val pi : double = 3.14159265359;
(*
 *
 * generally handy stuff
 *)
val EPSILON : double = 1.0e~6;
val INFINITY : double = 1.0e20;
fun map f = let
      fun mapf l = (case l of nil => nil | x::xs => f x :: mapf xs)
      in
	mapf
      end;
fun fold f = let
      fun foldf s0 = let
	    fun fold' l = (case l of nil => s0 | x::xs => f (x, foldf s0 xs))
	    in
	      fold'
	    end
      in
	foldf
      end;
fun hd l = (case l
       of nil => fail("expecting a head")
	| x::xs => x);
fun tl l = (case l
       of nil => fail("expecting a tail")
	| x::xs => xs);

(*
 * convenient vector operations
 *)
type vec = (double * double * double);
fun vecadd ((x1,y1,z1) : vec) = let fun add (x2,y2,z2) = (x1+x2, y1+y2, z1+z2) in add end;
fun vecsum (x : vec list) = let
      fun f (a, b) = vecadd a b
      in
	fold f (0.0,0.0,0.0) x
      end;
fun vecsub ((x1,y1,z1) : vec) = let fun sub (x2,y2,z2) = (x1-x2, y1-y2, z1-z2) in sub end;
fun vecmult ((x1,y1,z1) : vec) = let fun mul (x2,y2,z2) = (x1*x2, y1*y2, z1*z2) in mul end;
fun vecnorm ((x,y,z) : vec) = let
      val len = sqrt (x*x + y*y + z*z)
      in ((x/len, y/len, z/len), len) end;
fun vecscale ((x,y,z) : vec) = let fun scale a = (a*x, a*y, a*z) in scale end;
fun vecdot ((x1,y1,z1) : vec) = let fun dot (x2,y2,z2) = x1*x2 + y1*y2 + z1*z2 in dot end;
fun veccross ((x1,y1,z1) : vec) = let fun cross (x2,y2,z2) = (y1*z2-y2*z1, z1*x2-z2*x1, x1*y2-x2*y1) in cross end;
(* Note the following code is broken for negative vectors, but it was in the original
 * version.
 *)
fun zerovector ((x,y,z) : vec) =
      (x < EPSILON andalso y < EPSILON andalso z < EPSILON);

fun vec2s ( (x1,y1,z1):vec) = "["^dtos x1^", "^dtos y1^", "^dtos z1^"]";

(*
 * type declarations
 *)
datatype Light
  = Directional of (vec * vec)		(* direction, color *)
  | Point of (vec * vec)		(* position, color *)
  ;
fun lightcolor l = (case l
       of (Directional(_, c)) => c
	| (Point(_, c)) => c
      (* end case *));
datatype Surfspec
  = Ambient of vec	(* all but specpow default to zero *)
  | Diffuse of vec
  | Specular of vec
  | Specpow of double	(* default 8. *)
  | Reflect of double
  | Transmit of double
  | Refract of double	(* default 1, like air == no refraction *)
  | Body of vec		(* body color, default 1.,1.,1. *)
  ;

(* BUG: the CFG checker fails on a bogus type for surf *)
fun ambientsurf surf = (case surf
       of nil => (0.0, 0.0, 0.0)
	| (Ambient v :: ss) => (v : vec)
(*	| (_ :: ss) => ambientsurf ss*)
      (* end case *));
fun diffusesurf surf = (case surf
       of nil => (0.0, 0.0, 0.0)
	| (Diffuse v :: ss) => v
	| (_ :: ss) => diffusesurf ss
      (* end case *));
fun specularsurf surf = (case surf
       of nil => (0.0, 0.0, 0.0)
	| (Specular v :: ss) => v
	| (_ :: ss) => (specularsurf ss)
      (* end case *));
fun specpowsurf surf = (case surf
       of nil => 8.0
	| (Specpow r :: ss) => r
	| (_ :: ss) => specpowsurf ss
      (* end case *));
fun reflectsurf surf = (case surf
       of nil => 0.0
	| (Reflect r :: ss) => r
	| (_ :: ss) => reflectsurf ss
      (* end case *));
fun transmitsurf surf = (case surf
       of nil => 0.0
	| (Transmit r :: ss) => r
	| (_ :: ss) => transmitsurf ss
      (* end case *));
fun refractsurf surf = (case surf
       of nil => 1.0
	| (Refract r :: ss) => r
	| (_ :: ss) => refractsurf ss
      (* end case *));
fun bodysurf surf = (case surf
       of nil => (1.0,1.0,1.0)
	| (Body v :: ss) => v
	| (_ :: ss) => bodysurf ss
      (* end case *));

datatype Sphere = Sphere of vec * double * Surfspec list; (* pos, radius, surface type *)
fun spheresurf (Sphere(pos, rad, surf)) = surf;

fun sphere2s sp = (case sp
    of Sphere (center, r, _) => "center="^vec2s center^", r="^dtos r
    (* end case *));

(*
% camera static:
%   lookfrom = 0 -10 0   <--- Camera.pos
%   lookat = 0 0 0
%   vup = 0 0 1
%   fov = 45
% yields
%   dir = norm(lookat - lookfrom) = 0 1 0
%   lookdist = length(lookat-lookfrom) = 10
*)
(*
 * test conditions
 *)
(*val lookfrom = (0.0, (-10.0), 0.0);*)
val lookat = (0.0, 0.0, 0.0);
val vup = (0.0, 0.0, 1.0);
val fov = 45.0;
(*val background = (0.1, 0.1, 0.2);*)

val redsurf = (Ambient (0.1,0.0,0.0)) ::(Diffuse (0.3,0.0,0.0)) ::
	   (Specular (0.8,0.4,0.4)) :: (Transmit 0.7) :: nil;
val greensurf = (Ambient (0.0,0.1,0.0)) :: (Diffuse (0.0,0.3,0.0)) ::
	     (Specular (0.4,0.8,0.4)) :: nil;
val bluesurf = (Ambient (0.0,0.0,0.1)) :: (Diffuse (0.0,0.0,0.3)) ::
	    (Specular (0.4,0.4,0.8)) :: nil;

(*%%%%%%
%% interesting transmission test
% testspheres = ((Sphere (0.,0.,0.) 2. redsurf)::
% 	       (Sphere ((-2.1),(-2.),(-2.2)) .5 bluesurf)::
% 	       (Sphere ((-2.8),3.5,(-1.8)) 1.7 greensurf)::nil);
% testlights = (Directional (1.,(-1.),1.) (1.,1.,1.))::
% 	     (Point ((-3.),(-3.),(-3.)) (1.,1.,1.))::nil;
%%%%%%%
%% trivial transmission test
% testspheres = ((Sphere ((-1.5),0.,0.) 3. redsurf)::
% 	       (Sphere (1.5, 7.5, 0.) 4. greensurf)::nil);
%%%%%%%
%% reflection test
% mirrorsurf = ((Ambient (.04,.04,.04))::(Diffuse (.05,.05,.05))::
% 	      (Specular (.8,.8,.8))::(Specpow 60.)::(Reflect 1.)::nil);
% testspheres = ((Sphere ((-1.5),0.,0.) 2. mirrorsurf)::
% 	       (Sphere (1.,(-2.),(-.5)) 1. greensurf)::nil);
*)
(*%%%%%%
%% standard balls
*)
val s2 = (Ambient (0.035,0.0325,0.025)) :: (Diffuse(0.5,0.45,0.35)) ::
       (Specular(0.8,0.8,0.8)) :: (Specpow 3.0) :: (Reflect 0.5) :: nil;
val s3 = (Ambient (0.1,0.0,0.0)) :: (Diffuse (0.3,0.0,0.0)) ::
	   (Specular (0.8,0.4,0.4)) :: (Transmit 0.7) :: nil;
val testspheres =
     Sphere((0.0,0.0,0.0), 0.5, s3) ::
     Sphere((0.272166,0.272166,0.544331), 0.166667, s2) ::
     Sphere((0.643951,0.172546,0.0), 0.166667, s2) ::
     Sphere((0.172546,0.643951,0.0), 0.166667, s2) ::
     Sphere(((~0.371785),0.0996195,0.544331), 0.166667, s2) ::
     Sphere(((~0.471405),0.471405,0.0), 0.166667, s2) ::
     Sphere(((~0.643951),(~0.172546),0.0), 0.166667, s2) ::
     Sphere((0.0996195,(~0.371785),0.544331), 0.166667, s2) ::
     Sphere(((~0.172546),(~0.643951),0.0), 0.166667, s2) ::
     Sphere((0.471405,(~0.471405),0.0), 0.166667, s2) :: nil;
val testlights = Point((4.0,3.0,2.0), (0.288675,0.288675,0.288675)) ::
              Point((1.0, ~4.0,4.0), (0.288675,0.288675,0.288675)) ::
              Point((~3.0,1.0,5.0), (0.288675,0.288675,0.288675)) :: nil;
val lookfrom = (2.1, 1.3, 1.7);
val background = (0.078, 0.361, 0.753);
val world = testspheres;
(*%%%%%%%*)


(*%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% sphere specific items
%
% figure when a ray hits a sphere
%
%%% Assumes direction vector is normalized!
*)

fun sphereintersect (pos, dir, sp) = let
    fun unpack1 sp = (case sp
        of Sphere(center, rad, _) => center)
    fun unpack2 sp = (case sp
        of Sphere(center, rad, _) => rad)

    val center = unpack1 sp
    val rad = unpack2 sp

    val m = vecsub pos center;  (* x - center *)
    val m2 = vecdot m m;    (* (x-center).(x-center) *)
    val bm = vecdot m dir;  (* (x-center).dir *)
    val disc = bm * bm - m2 + rad * rad;  (* discriminant *)
    in
      if (disc < 0.0) then (false, 0.0)  (* imaginary solns only *)
      else let
	  val slo = ~bm - (sqrt disc);
	  val shi = ~bm + (sqrt disc);
	  in
	  if (slo < 0.0) then  (* pick smallest positive intersection *)
	      if (shi < 0.0) then (false, 0.0)
	      else (true, shi)
	  else (true, slo)
	  end
    end

(*
% for shading, need normal at a point
*)
and spherenormal (pos, sp) = let
    fun unpack1 sp = (case sp
        of Sphere(center, rad, _) => center)
    fun unpack2 sp = (case sp
        of Sphere(center, rad, _) => rad)

    val spos = unpack1 sp
    val rad = unpack2 sp
      in
	vecscale (vecsub pos spos) (1.0/rad)
      end

and trace (spheres, pos, dir) = let
    (* make a list of the distances to intersection for each hit object *)
    fun sphmap l = (case l
	   of nil => nil
	    | (x::xs) => let
	      val (hit, where') = sphereintersect (pos, dir, x)
	      in
		if hit then
		  (where', x) :: (sphmap xs)
		else
		  (sphmap xs)
	      end)
    val dists = sphmap spheres;
    (* return a sphere and its distance *)
    in
      case dists
       of nil => (false, INFINITY, (hd spheres))  (* missed all *)
        | first::rest => let
	    fun min ((d1, s1), (d2, s2)) = if (d1 < d2) then (d1,s1) else (d2,s2)
	    val (mindist, sp) = fold min first rest
	    in
	      (true, mindist, sp)
	    end
    end

and lightray (l, pos, norm, refl, surf) = let
    val (ldir, dist) = lightdirection (l, pos);
    val cosangle = vecdot ldir norm;  (* lightray is this far off normal *)
    val (inshadow, lcolor) = shadowed (pos, ldir, lightcolor l);
    in
    if (inshadow) then (0.0,0.0,0.0)
    else let
	val diff = diffusesurf surf;
	val spow = specpowsurf surf;  (* assumed trans is same as refl *)
	in
	if (cosangle <= 0.0) then let (* opposite side *)
	    val bodycol = bodysurf surf;
	    val cosalpha = ~(vecdot refl ldir);
	    val diffcont = vecmult (vecscale diff (~cosangle)) lcolor;
	    val speccont = if (cosalpha <= 0.0) then (0.0,0.0,0.0)
		else vecmult (vecscale bodycol (expt cosalpha spow)) lcolor;
	    in vecadd diffcont speccont
	end else let
	    val spec = specularsurf surf;
	    val cosalpha = vecdot refl ldir;  (* this far off refl ray (for spec) *)
	    val diffcont = vecmult (vecscale diff cosangle) lcolor;
	    val speccont = if (cosalpha <= 0.0) then (0.0,0.0,0.0)
		else vecmult (vecscale spec (expt cosalpha spow)) lcolor;
	    in vecadd diffcont speccont
	end
    end
end

and lightdirection (dir, pt) = (case dir
       of (Directional(dir, col)) => let
	    val (d,_) = vecnorm dir in (d, INFINITY) end
	| (Point(pos, col)) => vecnorm (vecsub pos pt)
      (* end case *))

and shadowed (pos, dir, lcolor) = let (* need to offset just a bit *)
    val (hit, dist, sp) = trace (world, vecadd pos (vecscale dir EPSILON), dir);
    in
      if (not hit) then (false, lcolor)
      else (true, lcolor)  (* for now *)
    end

and reflectray (pos, newdir, lights, intens, contrib, color) = fail "todo"
and transmitray (lights, color, pos, dir, index, intens, contrib, norm) = fail "todo"
    
and shade (lights, sp, lookpos, dir, dist, contrib) = let
    val hitpos = vecadd lookpos (vecscale dir dist);
    val ambientlight = (1.0, 1.0, 1.0);  (* full contribution as default *)
    val surf = spheresurf sp;
    val amb = vecmult ambientlight (ambientsurf surf);
    (*  reflected_ray_dir = incoming_dir - (2 cos theta) norm; *)
    val norm = spherenormal (hitpos, sp);
    val refl = vecadd dir (vecscale norm ((~2.0)*(vecdot dir norm)));
    (*  diff is diffuse and specular contribution *)
    fun lightray' l = lightray (l, hitpos, norm, refl, surf)
    val diff = vecsum (map lightray' lights);
    val transmitted = transmitsurf surf;
    val simple = vecadd amb diff;
    (* calculate transmitted ray; it adds onto "simple" *)
    val trintensity = vecscale (bodysurf surf) transmitted;
    val (tir, trcol) = if (transmitted < EPSILON) then (false, simple)
                    else let
                      val index = refractsurf surf;
                      in
			transmitray (lights, simple, hitpos, dir, index, trintensity,
			  contrib, norm)
                      end
    (*  reflected ray; in case of TIR, add transmitted component *)
    val reflsurf = vecscale (specularsurf surf) (reflectsurf surf);
    val reflectiv = if tir then (vecadd trintensity reflsurf) else reflsurf;
    val rcol = if (zerovector reflectiv) then
             trcol
           else
             reflectray (hitpos, refl, lights, reflectiv, contrib, trcol);
   in
     rcol
   end

(*
% color the given pixel
*)
and tracepixel (spheres, lights, x, y, firstray, scrnx, scrny) = let
  val pos = lookfrom;
  val (dir, _) = vecnorm (vecadd (vecadd firstray (vecscale scrnx (itod x)))
		    (vecscale scrny (itod y)));
  val (hit, dist, sp) = trace (spheres, pos, dir);  (* pick first intersection *)
						(* return color of the pixel x,y *)
  in
    if hit then
      shade (lights, sp, pos, dir, dist, (1.0,1.0,1.0))
    else
      background
  end
;

val pos = (0.0,0.0,~1.0);
val dir = (0.0,0.0,1.0);
val x = (Ambient pos) :: nil;
val y = ambientsurf x;
val sphere = Sphere((0.0,0.0,0.0), 0.5, s3);

val (intersects,slo) = sphereintersect (pos, dir, sphere);
print ((dtos slo)^"\n") 

