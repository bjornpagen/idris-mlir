// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-deduplicate: of each class of idr.funcs that are one function twice
// over, the lexicographically smallest stays, every use of the others
// names it, and it takes the locations of all of them. And when two
// functions are one, which raising asks of its consumers too.
#ifndef IDR_TRANSFORMS_DEDUPLICATE_H
#define IDR_TRANSFORMS_DEDUPLICATE_H

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"

#include "mlir/Pass/Pass.h"

#include "llvm/ADT/Hashing.h"

namespace idr {

#define GEN_PASS_DECL_IDRDEDUPLICATE
#include "idr/Transforms/Passes.h.inc"

namespace deduplicate {

// The hash of what two copies of one function share: its facts (every
// attribute but its name and `instance`) and its body, values and blocks
// numbered in the order they are met, locations aside, a reference to the
// function itself hashed alike in every function, and a reference to a
// function `renames` renames hashed as its new name.
llvm::hash_code hashFunction(FuncOp fn, const DataRemap::Renames &renames = {});

// Whether `lhs` and `rhs` are one function twice over: the same facts, and
// bodies that match op for op, a reference in `rhs` to itself read as one
// to `lhs`. A reference to any other function must name the same one in
// both once `renames` has renamed it.
bool sameFunction(FuncOp lhs, FuncOp rhs, const DataRemap::Renames &renames = {});

} // namespace deduplicate
} // namespace idr

#endif // IDR_TRANSFORMS_DEDUPLICATE_H
