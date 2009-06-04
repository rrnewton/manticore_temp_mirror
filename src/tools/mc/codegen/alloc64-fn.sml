(* alloc-fn.sml
 * 
 * COPYRIGHT (c) 2007 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 *
 * Generate code for allocating blocks of memory in the heap.
 *)

functor Alloc64Fn (
    structure MTy : MLRISC_TYPES
    structure Regs : MANTICORE_REGS
    structure Spec : TARGET_SPEC
    structure Types : ARCH_TYPES
    structure MLTreeComp : MLTREECOMP 
    structure VProcOps : VPROC_OPS
	where MTy = MTy
  ) : ALLOC = struct

    structure MTy = MTy
    structure T = MTy.T
    structure M = CFG
    structure Var = M.Var
    structure Ty = CFGTy
    structure W = Word64
    structure Cells = MLTreeComp.I.C

    val wordSzB = IntInf.toInt Spec.ABI.wordSzB
    val wordAlignB = IntInf.toInt Spec.ABI.wordAlignB

    fun wordLit i = T.LI (T.I.fromInt (MTy.wordTy, i))

  (* return the byte offset and type of the i'th element of a list of fields *)
    fun tupleOffset {tys, i} = let
	  fun offset (ty :: tys, j, sz) =
		if (j >= i) then sz
		else offset (tys, j+1, Types.alignedTySzB ty + sz)
	    | offset ([], _, _) = raise Fail(concat[
		  "offset ", Int.toString(List.length tys), " of type ",
		  CFGTyUtil.toString (M.T_Tuple (false, tys))
		])
	  in 
	    offset (tys, 0, 0) 
	  end

  (* compute the address of the ith element off of a 'base' address *)
    fun tupleAddrOf {mty : CFG.ty, i : int, base : T.rexp} = let
	  val offset = (case mty
		 of CFG.T_Tuple(_, tys) => tupleOffset {tys=tys, i=i}
		  | CFG.T_OpenTuple tys => tupleOffset {tys=tys, i=i}
		  | _ => raise Fail ("cannot offset from type " ^ CFGTyUtil.toString mty)
		(* end case *))
	  in
	    T.ADD (MTy.wordTy, base, wordLit offset)
	  end

  (* select the ith element off of a 'base' address *)
    fun select {lhsTy : CFG.ty, mty : CFG.ty, i : int, base : T.rexp} = let
          val (offset, lhsTyI) = (case mty
            of ( CFG.T_Tuple (_, tys) |
		 CFG.T_OpenTuple tys  ) => (tupleOffset {tys=tys, i=i}, List.nth(tys, i))
	     | _ => raise Fail ("cannot offset from type "^CFGTyUtil.toString mty))
	  val addr = T.ADD(MTy.wordTy, base, wordLit offset)
	  val ty = Types.szOf lhsTy
	  in 
	    case MTy.cfgTyToMLRisc lhsTyI
	     of MTy.K_FLOAT => MTy.FEXP (ty, T.FLOAD (ty, addr, ManticoreRegion.memory))
	      | MTy.K_INT => MTy.EXP (ty, T.LOAD (ty, addr, ManticoreRegion.memory))
	  end

  (* return true if the type may be represented by a pointer into the heap *)
    fun isHeapPointer CFG.T_Any = true
      | isHeapPointer (CFG.T_Tuple _) = true
      | isHeapPointer (CFG.T_OpenTuple _) = true
      | isHeapPointer _ = false

    fun setBit (w, i, ty) = if (isHeapPointer ty) then W.orb (w, W.<< (0w1, i)) else w

    fun initObj offAp ((ty, mltree), {i, stms, totalSize, ptrMask}) = let
	  val store = MTy.store (offAp totalSize, mltree, ManticoreRegion.memory)
	  val ptrMask' = setBit (ptrMask, Word.fromInt i, ty)
	  val totalSize' = Types.alignedTySzB ty + totalSize
	  in
	    {i=i+1, stms=store :: stms, totalSize=totalSize', ptrMask=ptrMask'}
	  end (* initObj *)

    fun allocMixedObj offAp args = let
	  val {i=nWords, stms, totalSize, ptrMask} = 
		List.foldl (initObj offAp) {i=0, stms=[], totalSize=0, ptrMask=0w0} args
	(* create the mixed-object header word *)
	  val hdrWord = W.toLargeInt (
		  W.orb (W.orb (W.<< (ptrMask, 0w7), 
				W.<< (W.fromInt nWords, 0w1)), 0w1) )
	  in	  
	    if ((IntInf.fromInt totalSize) > Spec.ABI.maxObjectSzB)
	      then raise Fail "object size too large"
	      else (totalSize, hdrWord, stms)
	  end (* allocMixedObj *)

    fun allocVectorObj offAp args = let
	  val {i=nWords, stms, totalSize, ...} =
	        List.foldl (initObj offAp) {i=0, stms=[], totalSize=0, ptrMask=0w0} args
	  val hdrWord = W.toLargeInt(W.+ (W.<< (W.fromInt nWords, 0w3), 0w4))
	  in
	    (totalSize, hdrWord, stms)
	  end

    fun allocRawObj offAp args = let
	  val {i=nWords, stms, totalSize, ...} =
	        List.foldl (initObj offAp) {i=0, stms=[], totalSize=0, ptrMask=0w0} args
	  val hdrWord = W.toLargeInt (W.+ (W.<< (W.fromInt nWords, 0w3), 0w2))
	  in
	    (totalSize, hdrWord, stms)
	  end (* allocRawObj *)

  (* determine the representation of an allocation and generate the appropriate
   * allocation code.
   *)
    fun alloc offAp args = let
	  fun lp (hasPtr, hasRaw, (x, _)::xs) = if isHeapPointer x
		  then lp(true, hasRaw, xs)
		else if CFGTyUtil.hasUniformRep x 
  	          then lp (hasPtr, hasRaw, xs)
		  else lp (hasPtr, true, xs)
	    | lp (true, false, []) = allocVectorObj offAp args
	    | lp (true, true, []) = allocMixedObj offAp args
	    | lp (false, _, []) = allocRawObj offAp args
	  val (totSz, hdr, stms) = lp (false, false, args)
	  in
	    (totSz, hdr, List.rev stms)
	  end

  (* allocate arguments in the local heap *)
    fun genAlloc {tys=[], ...} = (* an empty allocation generates a nil pointer *)
(* FIXME: this only happens because the closure-conversion doesn't deal with empty closures correctly *)
	  { ptr=MTy.EXP (MTy.wordTy, wordLit 1), stms=[] }
      | genAlloc {isMut, tys, args} = let
	  val args = ListPair.zipEq (tys, args)
	  fun offAp i = T.ADD(MTy.wordTy, T.REG(MTy.wordTy, Regs.apReg), wordLit i)
	  val (totalSize, hdrWord, stms) = alloc offAp args
	(* store the header word *)
	  val stms = MTy.store (offAp (~wordSzB), MTy.EXP (MTy.wordTy, T.LI hdrWord), ManticoreRegion.memory) :: stms
	(* ptrReg points to the first data word of the object *)
	  val ptrReg = Cells.newReg ()
	(* copy the original allocation pointer into ptrReg *)
	  val ptrMv = T.MV (MTy.wordTy, ptrReg, T.REG(MTy.wordTy, Regs.apReg))
	(* bump up the allocation pointer *)
	  val bumpAp = T.MV (MTy.wordTy, Regs.apReg, offAp (totalSize+wordSzB))
	  in
	    { ptr=MTy.GPR (MTy.wordTy, ptrReg), stms=stms @ [ptrMv, bumpAp] }
	  end (* genAlloc *)

  (* allocate arguments in the global heap *)
    fun genGlobalAlloc {tys=[], ...} = raise Fail "GAlloc[]"
      | genGlobalAlloc {isMut, tys, args} = let
	  val args = ListPair.zipEq (tys, args)
	  val (vpReg, setVP) = let
		val r = Cells.newReg()
		val MTy.EXP(_, hostVP) = VProcOps.genHostVP
		in
		  (T.REG(MTy.wordTy, r), T.MV(MTy.wordTy, r, hostVP))
		end
	  val (globalApReg, globalAp, setGAp, globalApAddr) = let
		val r = Cells.newReg()
		val MTy.EXP(_, gap) = MTy.EXP (64, VProcOps.genVPLoad' (MTy.wordTy, Spec.ABI.globNextW, vpReg))
		in
		  (r, T.REG(MTy.wordTy, r), T.MV(MTy.wordTy, r, gap), gap)
		end
	  fun offAp i = T.ADD (MTy.wordTy, globalAp, wordLit i)
	  val (totalSize, hdrWord, stms) = alloc offAp args
	(* store the header word *)
	  val stms = MTy.store (offAp (~wordSzB), MTy.EXP (MTy.wordTy, T.LI hdrWord), ManticoreRegion.memory) 
		:: stms
	(* bump up the allocation pointer *)
	  val bumpAp = VProcOps.genVPStore' (MTy.wordTy, Spec.ABI.globNextW, vpReg, 
			T.ADD (64, globalApAddr, wordLit (totalSize+wordSzB)))
	  in
	    { ptr=MTy.GPR (MTy.wordTy, globalApReg), stms=setVP :: setGAp :: stms @ [bumpAp] }
	  end

(* FIXME: this value should come from the runtime constants *)
    val heapSlopSzB = Word.- (Word.<< (0w1, 0w12), 0w512)

  (* This expression evaluates to true when the heap has enough space for szB
   * bytes.  There are 4kbytes of heap slop presubtracted from the limit pointer
   * So, most allocations need only perform the following check.
   * 
   * if (limReg - apReg <= 0)
   *    then continue;
   *    else doGC ();
   *)
    fun genAllocCheck szB =
	if Word.<= (szB, heapSlopSzB)
	then T.CMP (MTy.wordTy, T.Basis.LE, 
		    T.SUB (MTy.wordTy, T.REG (MTy.wordTy, Regs.limReg), T.REG (MTy.wordTy, Regs.apReg)),
		    T.LI 0)
	else T.CMP (MTy.wordTy, T.Basis.LE, 
		    T.SUB (MTy.wordTy, T.REG (MTy.wordTy, Regs.limReg), T.REG (MTy.wordTy, Regs.apReg)),
		    T.LI (Word.toLargeInt szB))

  (* This expression checks that there are at least szB bytes available in the
   * global heap.
   *
   *  if (globNextW + szB > globLimit)
   *     then continue;
   *     else doGC ();
   *)
(* FIXME: untested *)
    fun genGlobalAllocCheck szB = let
	val (vpReg, setVP) = let
	      val r = Cells.newReg()
	      val MTy.EXP(_, hostVP) = VProcOps.genHostVP
	      in
		 (T.REG(MTy.wordTy, r), T.MV(MTy.wordTy, r, hostVP))
	      end
	val globalAP = VProcOps.genVPLoad' (MTy.wordTy, Spec.ABI.globNextW, vpReg)
	val globalLP = VProcOps.genVPLoad' (MTy.wordTy, Spec.ABI.globLimit, vpReg)
	in
	    {stms=[ setVP ],
	     allocCheck=T.CMP (MTy.wordTy, T.Basis.LE,
			       T.SUB (MTy.wordTy, globalLP, globalAP),
			       T.LI (Word.toLargeInt szB))}
	end

  end (* Alloc64Fn *)
