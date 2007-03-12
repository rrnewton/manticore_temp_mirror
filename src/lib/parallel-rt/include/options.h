/* options.h
 *
 * COPYRIGHT (c) 2007 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 */

#ifndef _OPTIONS_H_
#define _OPTIONS_H_

#include "manticore-rt.h"

Options_t *InitOptions (int argc, const char **argv);

bool GetFlagOpt (Options_t *opts, const char *flg);
int GetIntOpt (Options_t *opts, const char *opt, int dflt);

/* get a size option; the suffixes "k" and "m" are supported */
Addr_t GetSizeOpt (Options_t *opts, const char *opt, Addr_t dfltScale, Addr_t dflt);

#endif /* !_OPTIONS_H_ */
