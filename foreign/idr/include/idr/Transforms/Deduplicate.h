// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-deduplicate: of each class of idr.funcs that are one function twice
// over, the first in symbol order stays and every use of the others names
// it. And when two functions are one, which raising asks of its consumers
// too.
//
// Two functions are one when their facts are equal and their bodies are
// equivalent op for op, upstream's equivalence, each symbol reference read
// as the class of the function it names: so callers that differ only in
// which copy they name are one, and so are copies of one recursion. The
// classes are found by partition refinement: split by facts and shape,
// then each class split by the classes its members' references name, until
// no class splits, which a partition that only refines reaches within as
// many rounds as there are functions.
#ifndef IDR_TRANSFORMS_DEDUPLICATE_H
#define IDR_TRANSFORMS_DEDUPLICATE_H

#include "idr/IR/IdrDialect.h"

#include "mlir/Pass/Pass.h"
#include "llvm/Support/xxhash.h"

namespace idr {

#define GEN_PASS_DECL_IDRDEDUPLICATE
#include "idr/Transforms/Passes.h.inc"

namespace deduplicate {

// The digest of a function's facts and body: values numbered in the order
// met, locations aside, every symbol reference read as one placeholder.
// Equal functions have equal digests in every process.
llvm::XXH128_hash_t structuralDigest(FuncOp fn);

// Whether two functions are one: equal facts, and bodies equivalent op for
// op, a reference to either read as the same.
bool equivalent(FuncOp lhs, FuncOp rhs);

} // namespace deduplicate
} // namespace idr

#endif // IDR_TRANSFORMS_DEDUPLICATE_H
