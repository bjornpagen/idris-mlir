// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Whether a call is inlined: MLton's per-function rule, decided once on the
// callee's final body and read at each call, and the most a caller may
// hold. The rule never refuses anything, it answers inline or keep. The
// facts are the optimizer's alone: they live on its node for its run and
// die with it, its inliner keeping the size current as it inlines.
#ifndef IDR_ANALYSIS_INLINE_H
#define IDR_ANALYSIS_INLINE_H

#include "idr/IR/IdrDialect.h"

#include <cstdint>
#include <variant>

namespace idr::inlining {

// MLton's numbers: a leaf of at most kLeafSize ops always inlines; any
// other function when (calls - 1) * (size - kSmall) <= kProduct.
inline constexpr std::int64_t kLeafSize = 40;
inline constexpr std::int64_t kSmall = 60;
inline constexpr std::int64_t kProduct = 320;
// The most ops a caller holds with a callee's body in it. The rule bounds
// a callee of two calls or more to 380 ops, so only a callee of one call
// can build a giant body: this is what bounds it.
inline constexpr std::int64_t kCallerCap = 10000;

// Where a function sits among the calls, as the program graph and the
// optimizer know it: on no cycle, or on one (a component of two or more,
// a call of itself, or a specialization that is one step of a recursion
// on static data, whose inlining would unroll the recursion into its
// callers). A function on a cycle is never inlined: its original could
// never go.
enum class Cycle : std::uint8_t { None, On };

// What a call reads of a final callee: keep its calls, or inline them, the
// body adding its size to each caller. The size is read only when
// inlining, so only that case holds it.
struct Keep {};
struct Inline {
  // How many operations the body holds: the return and every nested op
  // included, the function itself not.
  std::int64_t size;
};
using Verdict = std::variant<Keep, Inline>;

// How many operations the body of `fn` holds: what the rule weighs and
// what a caller's size grows by when the body is inlined into it.
std::int64_t sizeOf(idr::FuncOp fn);

// MLton's rule, decided once on the final body of `fn`, which `calls`
// call sites name (the program's idr.call sites naming it when the
// optimizer began; 1 for a specialization node, one per request): never
// on a cycle; always a leaf, a body with no idr.call, of at most kLeafSize
// ops; any other when (calls - 1) * (size - kSmall) <= kProduct. One walk
// of the body gives both the size and whether it is a leaf.
Verdict verdictOf(idr::FuncOp fn, std::uint32_t calls, Cycle cycle);

// Whether a caller of `callerSize` ops stays at or under kCallerCap with
// the call replaced by a body of `calleeSize` ops. A callee is one block,
// whose return inlining drops; `calleeSize` counts it all the same.
enum class Fit : std::uint8_t { Over, Within };
inline Fit fitsCap(std::int64_t callerSize, std::int64_t calleeSize) {
  return callerSize - 1 + calleeSize <= kCallerCap ? Fit::Within : Fit::Over;
}

} // namespace idr::inlining

#endif // IDR_ANALYSIS_INLINE_H
