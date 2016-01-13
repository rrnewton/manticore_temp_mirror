/* apply.c
 *
 * COPYRIGHT (c) 2007 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 */

#include "manticore-rt.h"
#include "vproc.h"
#include "gc.h"
#include "value.h"
#include "request-codes.h"
#include "scheduler.h"
#include "heap.h"
#include "inline-event-log.h"

extern RequestCode_t ASM_Apply (VProc_t *vp, Addr_t cp, Value_t arg, Value_t ep, Value_t rk, Value_t ek);
extern int ASM_Return;
extern int ASM_UncaughtExn;
extern int ASM_Resume;

/* \brief run a Manticore function f applied to arg.
 * \param vp the host vproc
 * \param f the Manticore function to apply
 * \param arg the Manticore value to apply \arg{f} to
 * \return the result of the application.
 */
Value_t ApplyFun (VProc_t *vp, Value_t f, Value_t arg)
{
  /* get the code and environment pointers for f */
    Addr_t cp = ValueToAddr (ValueToClosure(f)->cp);
    Value_t ep = ValueToClosure(f)->ep;

    RunManticore (vp, cp, arg, ep);

    return vp->stdArg;

} /* end of ApplyFun */


/* \brief Run Manticore code.
 * \param vp the host vproc
 * \param codeP the address of the code to run
 * \param arg the value of the standard argument register
 * \param envP the value of the standard environment-pointer register
 */
void RunManticore (VProc_t *vp, Addr_t codeP, Value_t arg, Value_t envP)
{
  /* allocate the return and exception continuation objects
   * in the VProc's heap.
   */
    Value_t retCont = WrapWord(vp, (Word_t)&ASM_Return);
    Value_t exnCont = WrapWord(vp, (Word_t)&ASM_UncaughtExn);

    while (1) {
#ifndef NDEBUG
	if (DebugFlg)
	    SayDebug("[%2d] ASM_Apply(%p, %p, %p, %p, %p, %p)\n",
                 vp->id, (void*)vp, (void*)codeP, (void*)arg, (void*)envP, (void*)retCont, (void*)exnCont);
#endif
	if (ShutdownFlg && !(vp->shutdownPending == M_TRUE)) {
	  /* schedule a continuation that will cleanly shut down the runtime */
	    envP = vp->shutdownCont;
	    codeP = ValueToAddr(ValueToCont(envP)->cp);
	    arg = M_UNIT;
	    retCont = M_UNIT;
	    exnCont = M_UNIT;
	    vp->atomic = M_TRUE;
	    vp->sigPending = M_FALSE;
	    vp->shutdownPending = M_TRUE;  // schedule the shutdown continuation just once
	}

	LogRunThread(vp, 0);
	RequestCode_t req = ASM_Apply (vp, codeP, arg, envP, retCont, exnCont);
	LogStopThread(vp, 0, 0); //thread id and stop status, TODO: these are currently unused

	Addr_t oldLimitPtr = SetLimitPtr(vp, LimitPtr(vp));

	switch (req) {
	  case REQ_GC:
	  /* check to see if we actually need to do a GC, since this request
	   * might be from a pending signal.
	   */
	    if ((LimitPtr(vp) < vp->allocPtr) || vp->globalGCPending) {
	      /* request a minor GC */
		MinorGC (vp);
	    }
	  /* check for asynchronous signals */
	    if (oldLimitPtr == 0) {
#ifndef NDEBUG
	      if (DebugFlg)
		SayDebug("Asynchronous signal arrived at vproc %d\n", vp->id);
#endif
	      /* an asynchronous signal has arrived */
	        vp->sigPending = M_TRUE;
	    }

	  /* is there a pending signal that we can deliver? */
	    if ((vp->sigPending == M_TRUE) && (vp->atomic == M_FALSE)) {
		Value_t resumeK = AllocNonUniform (vp, 3,
                                           INT(PtrToValue(&ASM_Resume)),
                                           INT(PtrToValue(vp->stdCont)),
                                           PTR(vp->stdEnvPtr));
	      /* pass the signal to scheduling code in the BOM runtime */
		envP = vp->schedCont;
		codeP = ValueToAddr(ValueToCont(envP)->cp);
		arg = resumeK;
		retCont = M_UNIT;
		exnCont = M_UNIT;
		vp->atomic = M_TRUE;
		vp->sigPending = M_FALSE;
		LogPreemptSignal(vp);
	    }
	    else {
	      /* setup the return from GC */
	      /* we need to invoke the stdCont to resume after GC */
		codeP = ValueToAddr (vp->stdCont);
		envP = vp->stdEnvPtr;
	      /* clear the dead registers */
		arg = M_UNIT;
		retCont = M_UNIT;
		exnCont = M_UNIT;
	    }
	    break;
	  case REQ_Return:	/* returning from a function call */
	  /* shutdown the runtime
	   * in the future we should create a new request code to handle shutdown.
	   */
	    ShutdownFlg = true;
	    for (int i = 0; i < NumVProcs; i++) {
	      /* force each vproc to check for shutdown */
		VProc_t *wvp = VProcs[i];
		VProcSendSignal(vp, wvp, wvp->currentFLS, wvp->dummyK);
		VProcPreempt (vp, wvp);
	    }
	    break;
	  case REQ_UncaughtExn:	/* raising an exception */
	    Die ("uncaught exception\n");
	  case REQ_Sleep:	/* make the VProc idle */
	    {
	       Value_t status = M_TRUE;
	       Time_t timeToSleep = *((Time_t*)(vp->stdArg));
	       if (timeToSleep == 0)    /* convention: if timeToSleep == 0, sleep indefinitely */
		   VProcSleep(vp);
	       else
		   status = VProcNanosleep(vp, timeToSleep);
	       assert (vp->wakeupCont != M_NIL);
	       envP = vp->wakeupCont;
	       codeP = ValueToAddr (ValueToCont(envP)->cp);
	       arg = AllocNonUniform (vp, 1, PTR(status));
	       retCont = M_UNIT;
	       exnCont = M_UNIT;
	       vp->wakeupCont = M_NIL;
	    }
	    break;
	  default:
	    Die("unknown signal %d\n", req);
	}
    }

} /* end of RunManticore */
