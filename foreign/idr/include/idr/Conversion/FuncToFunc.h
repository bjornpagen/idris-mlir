// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Phase 0 of idr-lower: the program's functions as the dialects bound for
// LLVM name them.

#ifndef IDR_CONVERSION_FUNCTOFUNC_H
#define IDR_CONVERSION_FUNCTOFUNC_H

#include "idr/IR/IdrDialect.h"

namespace idr::conversion {

// Every function of `program` takes its mangled name, at every use of it
// (the program's root, each call, any other reference): one map, from each
// idr.func's name to its mangling, applied once by MLIR's replacer. Then
// every idr.func becomes, where it is, a func.func at the same location, of
// the same type, under that name, with its body and none of its facts:
// private, but for the program's root, which the outside enters and so stays
// public. Every idr.call becomes a func.call and every idr.return a
// func.return. Fails, having reported it, where a mangled name is the name
// of another symbol of the program.
mlir::LogicalResult lowerFunctions(ProgramOp program);

} // namespace idr::conversion

#endif // IDR_CONVERSION_FUNCTOFUNC_H
