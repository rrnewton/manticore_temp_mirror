#!/bin/sh
#
# COPYRIGHT (c) 2008 Manticore project. (http://manticore.cs.uchicago.edu)
# All rights reserved.
#
# This script is run as part of the configuration process to generate
# the runtime-constants.sml file.
#

BUILD_DIR=src/lib/parallel-rt/build/config

function gen {
  PROG=$1
  OUTFILE=$2
  (cd $BUILD_DIR; make $PROG || exit 1)

  echo "$BUILD_DIR/$PROG > $OUTFILE"
  $BUILD_DIR/$PROG > $OUTFILE

  rm -f $BUILD_DIR/$PROG
}

gen gen-runtime-constants src/tools/mc/driver/runtime-constants.sml
gen gen-basis-offsets src/lib/basis/include/runtime-offsets.def

# the logging support files are generated by the log-gen tool
#
(cd src/gen/log-gen; make local-install)
bin/log-gen

exit 0
