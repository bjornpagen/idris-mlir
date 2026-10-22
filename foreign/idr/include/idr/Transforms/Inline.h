// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Inlining: leaf inlining inside idr-optimize's specialize phase, and
// idr-inline, upstream's inliner on the final graph with the verdict as its
// profitability and the e-graph as its simplification. (`inline` is a
// keyword, so the area's namespace is `inlining`.)
//
// A leaf (a final body that calls nothing, of at most kLeafSize ops) is
// inlined wherever it is called, while specialization is still running: it
// cannot unroll anything and needs no count, and inlining it shows the
// constructors a caller's other calls are keyed on. Every other verdict is
// decided once, on the final program graph, where every call site of a
// callee is counted, and is never a refusal: a call it keeps is a call.
#ifndef IDR_TRANSFORMS_INLINE_H
#define IDR_TRANSFORMS_INLINE_H

#include "idr/Analysis/Inline.h"
#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/Pass/Pass.h"
#include "mlir/Transforms/Inliner.h"

#include <cstdint>
#include <memory>
#include <variant>

namespace idr::optimize {
class Schedule;
} // namespace idr::optimize

namespace idr {

#define GEN_PASS_DECL_IDRINLINE
#include "idr/Transforms/Passes.h.inc"

} // namespace idr

namespace idr::inlining {

// What a final body tells the verdict: its size in ops, and whether it
// calls anything.
enum class Calls : bool { None, Some };
struct Body {
  std::int64_t size = 0;
  Calls calls = Calls::Some;
};
Body bodyOf(FuncOp fn);

// Whether a call of a function inlines it, decided once per final
// function. Kept: on its caller's cycle, where its original could never
// go, or past the caller's size. A leaf always inlines; any other function
// when (calls - 1) * (size - kSmall) <= kProduct, its calls counted on the
// final graph.
enum class Reason : std::uint8_t { Cycle, Cap };
struct Keep {
  Reason reason;
};
struct Leaf {};
struct Weighed {
  std::int64_t size;
  std::uint32_t calls;
};
using Verdict = std::variant<Keep, Leaf, Weighed>;

// The verdict of `callee` at a call from `caller`, read off the final
// graph: its component, its call sites and its body.
Verdict verdictOf(const solver::ProgramGraph &graph, solver::FunctionId caller,
                  solver::FunctionId callee, const Body &body);

// The profitability upstream's inliner asks of each call: the callee's
// verdict, a weighed one accepted by MLton's product rule, and the caller
// kept within kCallerCap. Asked from one thread, in the inliner's order, so
// the running sizes it keeps are the same at any thread count.
class Profitability {
public:
  explicit Profitability(const solver::ProgramGraph &graph);
  bool operator()(const mlir::Inliner::ResolvedCall &call);
  std::uint64_t inlined() const { return numInlined; }
  std::uint64_t capped() const { return numCapped; }

private:
  const solver::ProgramGraph &graph;
  // Each function's size now, walked once and kept current by every inline
  // this answers.
  llvm::DenseMap<solver::FunctionId, std::int64_t> sizes;
  llvm::DenseMap<solver::FunctionId, Body> bodies;
  std::uint64_t numInlined = 0, numCapped = 0;
};

// The inner pipeline's leaf inlining, for one run: each call of a final
// callee whose body is a leaf is inlined, while the caller stays within
// kCallerCap; it counts what it inlined into `inlined`.
std::unique_ptr<mlir::Pass> createInlineLeaves(optimize::Schedule &schedule,
                                               mlir::Pass::Statistic &inlined);

} // namespace idr::inlining

#endif // IDR_TRANSFORMS_INLINE_H
