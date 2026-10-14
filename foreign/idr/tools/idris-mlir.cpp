// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idris-mlir: the one user command. Idris source or an idr module in, an
// executable (or with -c an object) out: the frontend beside it for Idris
// source, the pipeline in process, then the pinned clang to link. The
// driver is lib/Driver.

#include "idr/Driver/Main.h"

int main(int argc, char **argv) { return idr::driver::main(argc, argv); }
