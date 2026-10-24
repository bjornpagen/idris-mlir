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

#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Id.h"

#include "mlir/Pass/Pass.h"
#include "mlir/Transforms/Inliner.h"

#include <cstdint>
#include <memory>
#include <optional>
#include <variant>

namespace idr::optimize {
class Schedule;
} // namespace idr::optimize

namespace idr {

#define GEN_PASS_DECL_IDRINLINE
#include "idr/Transforms/Passes.h.inc"

} // namespace idr

namespace idr::inlining {

// The inliner's budget: MLton's numbers, in ops and call sites, which weigh
// whether a callee's body is worth copying into its callers. A leaf, a
// body that calls nothing, of at most kLeafSize ops always inlines; any
// other body when (calls - 1) * (size - kSmall) <= kProduct.
inline constexpr std::int64_t kLeafSize = 40;
inline constexpr std::int64_t kSmall = 60;
inline constexpr std::int64_t kProduct = 320;
// The most ops a caller holds with a callee's body in it. The product rule
// bounds a callee of two calls or more to 380 ops, so only a callee of one
// call can build a giant body: this is what bounds it.
inline constexpr std::int64_t kCallerCap = 10000;

// Whether a caller of `callerSize` ops stays at or under kCallerCap with
// the call replaced by a body of `calleeSize` ops. A callee is one block,
// whose return inlining drops; `calleeSize` counts it all the same.
enum class Fit : std::uint8_t { Over, Within };
inline Fit fitsCap(std::int64_t callerSize, std::int64_t calleeSize) {
  return callerSize - 1 + calleeSize <= kCallerCap ? Fit::Within : Fit::Over;
}

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
// go, but for a beta step, whose body calls the recursion and never
// itself; or a step of a recursion on static data anywhere, since each
// step has one call and inlining it hands its caller the next step's call,
// so the recursion would unroll into its callers up to the caller's cap.
// A leaf always inlines; any other function when
// (calls - 1) * (size - kSmall) <= kProduct, its calls counted on the
// final graph. The caller's cap is the profitability's, at each call.
enum class Reason : std::uint8_t { Cycle, Step };
struct Keep {
  Reason reason;
};
struct Leaf {};
struct Weighed {
  std::int64_t size;
  std::uint32_t calls;
};
using Verdict = std::variant<Keep, Leaf, Weighed>;

// The leaf rule, the one place it is written: a body that calls nothing,
// of at most kLeafSize ops, is a leaf; none for any other. The verdict and
// leaf inlining both ask it.
std::optional<Leaf> leafOf(const Body &body);

// The verdict of `callee` at a call from `caller`, read off the final
// graph (its component, its call sites), its body and what kind of copy
// it is (its `copy`).
Verdict verdictOf(const solver::ProgramGraph &graph, solver::FunctionId caller,
                  solver::FunctionId callee, const Body &body, std::optional<CopyKind> copy);

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
  // How many calls this answered to inline into `caller`: a function with
  // any is one inlining changed.
  std::uint32_t inlinedInto(solver::FunctionId caller) const { return into[caller]; }

private:
  const solver::ProgramGraph &graph;
  // Each caller's size now, walked the first time it is asked and kept
  // current by every inline this answers; each callee's body, walked the
  // first time it is asked. Indexed by the graph's ids, so the tables count
  // in the pass's footprint.
  IndexVector<solver::FunctionId, std::optional<std::int64_t>> sizes;
  IndexVector<solver::FunctionId, std::optional<Body>> bodies;
  IndexVector<solver::FunctionId, std::uint32_t> into;
  std::uint64_t numInlined = 0, numCapped = 0;
};

// The inner pipeline's leaf inlining, for one run: each call of a final
// callee whose body is a leaf is inlined, while the caller stays within
// kCallerCap; it counts what it inlined into `inlined`.
std::unique_ptr<mlir::Pass> createInlineLeaves(optimize::Schedule &schedule,
                                               mlir::Pass::Statistic &inlined);

} // namespace idr::inlining

#endif // IDR_TRANSFORMS_INLINE_H
