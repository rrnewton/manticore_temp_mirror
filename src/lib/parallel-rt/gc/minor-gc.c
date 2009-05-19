/* minor-gc.c
 *
 * COPYRIGHT (c) 2007 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 *
 * Minor GCs are local collections of a vproc's allocation space.
 */

#include <strings.h>
#include <stdio.h>

#include "manticore-rt.h"
#include "heap.h"
#include "gc.h"
#include "vproc.h"
#include "value.h"
#include "internal-heap.h"
#include "gc-inline.h"
#include "inline-log.h"
#include "bibop.h"

extern Addr_t	MajorGCThreshold; /* when the size of the nursery goes below this limit */
				/* it is time to do a GC. */

#ifdef NO_GC_STATS
#  define INCR_STAT(cntr) 	do { } while (0)
#else
#  define INCR_STAT(cntr)	do { (cntr)++; } while (0)
#endif

#ifndef NDEBUG
static void CheckMinorGC (VProc_t *self, Value_t **roots);
#endif

/* Copy an object to the old region */
STATIC_INLINE Value_t ForwardObj (Value_t v, Word_t **nextW)
{
    Word_t	*p = (Word_t *)ValueToPtr(v);
    Word_t	hdr = p[-1];
    if (isForwardPtr(hdr))
	return PtrToValue(GetForwardPtr(hdr));
    else {
	int len = GetLength(hdr);
	Word_t *newObj = *nextW;
	newObj[-1] = hdr;
	for (int i = 0;  i < len;  i++) {
	    newObj[i] = p[i];
	}
	*nextW = newObj+len+1;
	p[-1] = MakeForwardPtr(hdr, newObj);
	return PtrToValue(newObj);
    }

}

/* MinorGC:
 */
void MinorGC (VProc_t *vp)
{
    LogMinorGCStart (vp);

    Addr_t	nurseryBase = vp->nurseryBase;
    Addr_t	allocSzB = vp->allocPtr - nurseryBase - WORD_SZB;
    Word_t	*nextScan = (Word_t *)(vp->oldTop); /* current top of to-space */
    Word_t	*nextW = nextScan + 1;		/* next object address in to-space */

    assert (VProcHeap(vp) <= (Addr_t)nextScan);
    assert ((Addr_t)nextScan < vp->nurseryBase);
    assert (vp->nurseryBase < vp->allocPtr);

#ifndef NDEBUG
    if (GCDebug >= GC_DEBUG_MINOR)
	SayDebug("[%2d] Minor GC starting\n", vp->id);
#endif

#ifndef NO_GC_STATS
    vp->nLocalPtrs = 0;
    vp->nGlobPtrs = 0;
#endif

  /* gather the roots.  The protocol is that the stdCont register holds
   * the return address (which is not in the heap) and that the stdEnvPtr
   * holds the GC root.
   */
    Value_t *roots[16], **rp;
    rp = roots;
    *rp++ = &(vp->currentFLS);
    *rp++ = &(vp->actionStk);
    *rp++ = &(vp->schedCont);
    *rp++ = &(vp->dummyK);
    *rp++ = &(vp->wakeupCont);
    *rp++ = &(vp->rdyQHd);
    *rp++ = &(vp->rdyQTl);
    *rp++ = &(vp->landingPad);
    *rp++ = &(vp->stdEnvPtr);
    *rp++ = 0;
    assert (rp <= roots+(sizeof(roots)/sizeof(Value_t *)));

#ifndef NDEBUG
  /* nullify non-live registers */
    vp->stdArg = M_UNIT;
    vp->stdExnCont = M_UNIT;
#endif

  /* process the roots */
    for (int i = 0;  roots[i] != 0;  i++) {
	Value_t p = *roots[i];
	if (isPtr(p)) {
	    if (inAddrRange(nurseryBase, allocSzB, ValueToAddr(p))) {
		INCR_STAT(vp->nLocalPtrs);
		*roots[i] = ForwardObj(p, &nextW);
	    }
	    else
		INCR_STAT(vp->nGlobPtrs);
	}
    }

  /* scan to space */
    while (nextScan < nextW-1) {
	assert ((Addr_t)(nextW-1) <= vp->nurseryBase);
	Word_t hdr = *nextScan++;	// get object header
	if (isMixedHdr(hdr)) {
	  // a record
	    Word_t tagBits = GetMixedBits(hdr);
	    assert ((uint64_t)tagBits < (1l << (uint64_t)GetMixedSizeW(hdr)));
	    Value_t *scanP = (Value_t *)nextScan;
	    while (tagBits != 0) {
		if (tagBits & 0x1) {
		    Value_t v = *scanP;
		    if (isPtr(v)) {
			if (inAddrRange(nurseryBase, allocSzB, ValueToAddr(v))) {
			    INCR_STAT(vp->nLocalPtrs);
			    *scanP = ForwardObj(v, &nextW);
			}
			else
			    INCR_STAT(vp->nGlobPtrs);
		    }
		}
		tagBits >>= 1;
		scanP++;
	    }
	    nextScan += GetMixedSizeW(hdr);
	}
	else if (isVectorHdr(hdr)) {
	  // an array of pointers
	    int len = GetVectorLen(hdr);
	    for (int i = 0;  i < len;  i++, nextScan++) {
		Value_t v = *(Value_t *)nextScan;
		if (isPtr(v)) {
		    if (inAddrRange(nurseryBase, allocSzB, ValueToAddr(v))) {
			INCR_STAT(vp->nLocalPtrs);
			*nextScan = (Word_t)ForwardObj(v, &nextW);
		    }
		    else
			INCR_STAT(vp->nGlobPtrs);
		}
	    }
	}
	else {
	  // we can just skip raw objects
	    assert (isRawHdr(hdr));
	    nextScan += GetRawSizeW(hdr);
	}
    }

    assert ((Addr_t)nextScan >= VProcHeap(vp));
    Addr_t avail = VP_HEAP_SZB - ((Addr_t)nextScan - VProcHeap(vp));
#ifndef NDEBUG
    if (GCDebug >= GC_DEBUG_MINOR) {
	SayDebug("[%2d] Minor GC finished: %ld/%ld bytes live; %d available\n",
	    vp->id, (Addr_t)nextScan - vp->oldTop,
	    vp->allocPtr - vp->nurseryBase - WORD_SZB,
	    (int)avail);
#ifndef NO_GC_STATS
	SayDebug("[%2d] pointers scanned: %d local / %d global\n",
	    vp->id, vp->nLocalPtrs, vp->nGlobPtrs);
#endif /* !NO_GC_STATS */
    }
#endif /* !NDEBUG */

    LogMinorGCEnd (vp);

    if ((avail < MajorGCThreshold) || vp->globalGCPending) {
      /* time to do a major collection. */
	MajorGC (vp, roots, (Addr_t)nextScan);
    }
    else {
      /* remember information about the final state of the heap */
	vp->oldTop = (Addr_t)nextScan;
    }

#ifndef NDEBUG
    CheckMinorGC (vp, roots);
#endif

  /* reset the allocation pointer */
    SetAllocPtr (vp);

}

#ifndef NDEBUG
static void CheckLocalPtr (VProc_t *self, void *addr, const char *where)
{
    Value_t v = *(Value_t *)addr;
    if (isPtr(v)) {
	MemChunk_t *cq = AddrToChunk(ValueToAddr(v));
	if (cq->sts == TO_SP_CHUNK)
	    return;
	else if (cq->sts == FROM_SP_CHUNK)
	    SayDebug("CheckLocalPtr: unexpected from-space pointer %p at %p in %s\n",
		ValueToPtr(v), addr, where);
	else if (IS_VPROC_CHUNK(cq->sts)) {
	    if (cq->sts != VPROC_CHUNK(self->id)) {
		SayDebug("CheckLocalPtr: unexpected remote pointer %p at %p in %s\n",
		    ValueToPtr(v), addr, where);
	    }
	    else if (! inAddrRange(VProcHeap(self), self->oldTop - VProcHeap(self), ValueToAddr(v))) {
		SayDebug("CheckLocalPtr: local pointer %p at %p in %s is out of bounds\n",
		    ValueToPtr(v), addr, where);
	    }
	}
	else if (cq->sts == FREE_CHUNK) {
	    SayDebug("CheckLocalPtr: unexpected free-space pointer %p at %p in %s\n",
		ValueToPtr(v), addr, where);
	}
    }
}

static void CheckMinorGC (VProc_t *self, Value_t **roots)
{

  // check the roots
    for (int i = 0;  roots[i] != 0;  i++) {
	char buf[16];
	sprintf(buf, "root[%d]", i);
	Value_t v = *roots[i];
	CheckLocalPtr (self, roots[i], buf);
    }

  // check the local heap
    {
	Word_t *top = (Word_t *)(self->oldTop);
	Word_t *p = (Word_t *)VProcHeap(self);
	while (p < top) {
	    Word_t hdr = *p++;
	    if (isMixedHdr(hdr)) {
	      // a record
		Word_t tagBits = GetMixedBits(hdr);
		Word_t *scanP = p;
		while (tagBits != 0) {
		    if (tagBits & 0x1) {
			CheckLocalPtr (self, p, "local mixed object");
		    }
		    else {
		      /* check for possible pointers in non-pointer fields */
			Value_t v = *(Value_t *)scanP;
			if (isPtr(v)) {
			    MemChunk_t *cq = AddrToChunk(ValueToAddr(v));
			    switch (cq->sts) {
			      case FREE_CHUNK:
				SayDebug(" ** possible free-space pointer %p in mixed object %p+%d\n",
				    v, p, scanP-p);
				break;
			      case TO_SP_CHUNK:
				SayDebug(" ** possible to-space pointer %p in mixed object %p+%d\n",
				    v, p, scanP-p);
				break;
			      case FROM_SP_CHUNK:
				SayDebug(" ** possible from-space pointer %p in mixed object %p+%d\n",
				    v, p, scanP-p);
				break;
			      case UNMAPPED_CHUNK:
				break;
			      default:
				if (IS_VPROC_CHUNK(cq->sts)) {
				  /* the vproc pointer is pretty common, so filter it out */
				    if ((Addr_t)v & ~VP_HEAP_MASK != (Addr_t)v)
					SayDebug(" ** possible local pointer %p in mixed object %p+%d\n",
					    v, p, scanP-p);
				}
				else {
				    SayDebug(" ** strange pointer %p in mixed object %p+%d\n",
					v, p, scanP-p);
				}
				break;
			    }
			}
		    }
		    tagBits >>= 1;
		    scanP++;
		}
		p += GetMixedSizeW(hdr);
	    }
	    else if (isVectorHdr(hdr)) {
	      // an array of pointers
		int len = GetVectorLen(hdr);
		for (int i = 0;  i < len;  i++, p++) {
		    CheckLocalPtr (self, p, "local vector");
		}
	    }
	    else if (isForwardPtr(hdr)) {
	      // forward pointer
		Word_t *forwardPtr = GetForwardPtr(hdr);
		CheckLocalPtr(self, forwardPtr, "forward pointer");
		Word_t hdr = forwardPtr[-1];
		if (isMixedHdr(hdr)) {
		    p += GetMixedSizeW(hdr);
		}
		else if (isVectorHdr(hdr)) {
		    p += GetVectorLen(hdr);
		}
		else {
		    assert (isRawHdr(hdr));
		    p += GetRawSizeW(hdr);
		}
	    }
	    else {
		assert (isRawHdr(hdr));
	      // we can just skip raw objects
		p += GetRawSizeW(hdr);
	    }
	}
    }

}
#endif /* NDEBUG */
