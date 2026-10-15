// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The one canonicalizer every pipeline of ours runs
// (lib/Transforms/Canonicalize/Canonicalizer.cpp): the canonicalization
// patterns of every loaded dialect and registered op, collected as
// upstream's canonicalizer collects them, under upstream's greedy driver.
// It differs from upstream's pass in what it is given and what it checks,
// never in which patterns run:
//   - The patterns that move an op across others (sinking, case-of-case,
//     an element's update) ask what a call does, which is its callee's
//     effects, read through the program's symbol table (CalleeEffects).
//     MLIR gives a pattern no state of a run, so the table is the pass's
//     own: given when the pass is built, it is bound into those patterns
//     once, when the pass collects them. A pipeline built for one run of a
//     pass over a program (idr-optimize's inner pipeline) gives that run's
//     table; one built before any program exists gives none, and a call
//     may then do anything.
//   - Convergence is what each pattern is written for: what it matches on
//     is reached through operands and users, or it is tried at every op,
//     so that one sweep of the driver sees every consequence of a rewrite.
//     A pattern that moves an op across others asks of the ops between two
//     whether they only compute, which no operand or user links: when it
//     moves an op that does more than compute out from between others, it
//     tells the driver to try again the ops it moved it across
//     (CalleePattern::retryBetween). An op that
//     a fold or another pattern makes do less where it stands (a guard
//     known to hold, a force of a known suspension, a match that lost an
//     effectful case) is seen on the driver's next sweep: the pairs it
//     stood between end anywhere after it, and a folder has no rewriter to
//     tell the driver through. So is a constant a consumer uses, made after
//     the match, that the driver itself moves to the front of its block
//     when it next collects a region's constants, and tells no op of.
//     A function the patterns have not converged on within the greedy
//     driver's iteration limit is left less canonical, never refused, and
//     counted (the `not-converged` statistic). The `test-convergence`
//     option, as upstream's canonicalizer has it, makes that a failure: a
//     test turns it on to state that the patterns converge on its input.
//     Both are declared with the pass's entry in Passes.td.
//
// Region simplification is disabled. The greedy driver would otherwise
// re-simplify the region tree (dead block arguments, dead blocks, block
// merging at its aggressive level) after every pattern iteration, on every
// function, each time idr-optimize's inner pipeline runs on it; its cost
// grows with the bodies inlining builds, and the passes around the
// canonicalizer (CSE, remove-dead-values) already remove what it would.
// The worklist is seeded top-down, as upstream's canonicalizer seeds it.
#ifndef IDR_TRANSFORMS_CANONICALIZE_H
#define IDR_TRANSFORMS_CANONICALIZE_H

#include "mlir/Pass/Pass.h"

#include <memory>

namespace idr {

struct CalleeEffects;

// The registry's entry, `idr-canonicalize`, whose constructor is the one
// below with no table, as upstream's `--canonicalize` has none.
#define GEN_PASS_DECL_IDRCANONICALIZE
#include "idr/Transforms/Passes.h.inc"

// The canonicalizer, its call-aware patterns given `callees`, which must
// outlive the pass and every copy of it, or no table.
std::unique_ptr<mlir::Pass> createCanonicalizerPass(const CalleeEffects *callees);


} // namespace idr

#endif // IDR_TRANSFORMS_CANONICALIZE_H
