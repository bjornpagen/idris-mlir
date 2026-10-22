// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Counting: every reference made explicit on the grades the types already
// hold, as passes nested on idr.func that the pass manager runs in
// parallel, but for the one that writes signatures; a function reads its
// own body, its own signature and its callees' signatures, and no fact of
// one pass reaches the next but through the IR. In the pipeline's order, between the steps of other areas:
//   - idr-rc-cells: memory made explicit. A constructor of a cell becomes
//     the cell's source and its initialization, a select of references a
//     match, and each crossing with upstream's buffer ops an op of its own;
//   - (lifetimes decide where memory comes from);
//   - idr-rc-borrows, on the program: borrow inference's answer written
//     into the signatures, a parameter it makes a view graded `scoped` with
//     every value read from it, and each call or jump that passes a counted
//     value to a view lending it for the call;
//   - idr-rc-place: one reverse walk per function places the dups and
//     drops of the values their counts free; where a value of a known
//     constructor dies while parts of it live on, it is taken apart there
//     (drop specialization), and a part read while its owner lives takes a
//     dup from the owner where a use consumes it;
//   - (exclusivity proves sharing, which the grades then say);
//   - idr-rc-reuse: one forward walk per function turns a dead cell into a
//     construction of its size, the token carried across a match's rejoin
//     as a result, and lowers each rebuild the in-place rule decided; then
//     the function keeps its frame bound (`frame_bound`), the most bytes
//     its tokens hold where memory may be acquired;
//   - idr-rc-expand: each take of a value whose grade claims no uniqueness
//     becomes a match on uniqueness of two regions, the only test of
//     sharing left to run, so the lowering decides nothing.
// Counting walks; it never rewrites greedily, and it refuses nothing: a
// promise it cannot keep is an internal error.
#ifndef IDR_TRANSFORMS_COUNTING_H
#define IDR_TRANSFORMS_COUNTING_H

#include "idr/IR/IdrDialect.h"

#include "mlir/Pass/Pass.h"

namespace idr {

#define GEN_PASS_DECL_IDRRCCELLS
#define GEN_PASS_DECL_IDRRCBORROWS
#define GEN_PASS_DECL_IDRRCPLACE
#define GEN_PASS_DECL_IDRRCREUSE
#define GEN_PASS_DECL_IDRRCEXPAND
#include "idr/Transforms/Passes.h.inc"

} // namespace idr

#endif // IDR_TRANSFORMS_COUNTING_H
