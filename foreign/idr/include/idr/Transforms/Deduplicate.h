// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-deduplicate: of each class of private idr.funcs that are one function
// twice over, the lexicographically smallest stays, every use of the others
// names it, and it takes the locations of all of them.
#ifndef IDR_TRANSFORMS_DEDUPLICATE_H
#define IDR_TRANSFORMS_DEDUPLICATE_H

#include "idr/IR/IdrDialect.h"

#include "mlir/Pass/Pass.h"

#include "llvm/ADT/Hashing.h"

namespace idr {

#define GEN_PASS_DECL_IDRDEDUPLICATE
#include "idr/Transforms/Passes.h.inc"

namespace deduplicate {

// The hash of what two copies of one function share: its facts (every
// attribute but its name and `instance`) and its body, values and blocks
// numbered in the order they are met, locations aside, a reference to the
// function itself hashed as one.
llvm::hash_code hashFunction(FuncOp fn);

// Whether `lhs` and `rhs` are one function twice over: the same facts, and
// bodies that match op for op, a reference to itself in each counting as
// the same. A reference to any other function must name the same one in
// both.
bool sameFunction(FuncOp lhs, FuncOp rhs);

} // namespace deduplicate
} // namespace idr

#endif // IDR_TRANSFORMS_DEDUPLICATE_H
