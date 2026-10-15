// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Whether a call is inlined: MLton's per-function rule, read at the call
// on the callee's final body, and the most a caller may hold. The rule is
// a function of the callee's facts and the caller's size alone; it never
// refuses anything, it answers inline or keep.
#ifndef IDR_ANALYSIS_INLINE_H
#define IDR_ANALYSIS_INLINE_H

#include "idr/IR/IdrDialect.h"

#include <cstdint>

namespace idr {

// How many operations the body of `fn` holds: what a walk of it counts,
// the return and every nested op included, the function itself not.
int64_t inlineSize(idr::FuncOp fn);

namespace inlining {

// MLton's numbers: a leaf of at most kLeafSize ops always inlines; any
// other function when (calls - 1) * (size - kSmall) <= kProduct.
inline constexpr int64_t kLeafSize = 40;
inline constexpr int64_t kSmall = 60;
inline constexpr int64_t kProduct = 320;
// The most ops a caller holds with a callee's body in it. The rule bounds
// a callee of two calls or more to 380 ops, so only a callee of one call
// can build a giant body, and the greedy patterns over one body run on
// one worker: this is what bounds it.
inline constexpr int64_t kCallerCap = 10000;

// What the rule reads of a callee, all of it fixed once the callee is
// final.
struct Facts {
  // inlineSize of the final body.
  int64_t size = 0;
  // The program's idr.call sites naming the function when idr-optimize
  // began; 1 for a specialization node, one per request.
  unsigned calls = 0;
  // The final body holds no idr.call.
  bool leaf = false;
  // A member of a final component of two or more, or a final body that
  // calls the function itself: its original could never go.
  bool onCycle = false;
};

// MLton's rule on a final callee: never one on a cycle or one the
// frontend marked `no_inline`; a leaf of at most kLeafSize ops; any other
// when (calls - 1) * (size - kSmall) <= kProduct.
bool worthInlining(const Facts &callee, bool noInline);

// Whether a caller of `callerSize` ops stays at or under kCallerCap with
// the call replaced by a body of `calleeSize` ops, its return standing for
// the branch a body of several blocks becomes.
inline bool fitsCap(int64_t callerSize, int64_t calleeSize) {
  return callerSize - 1 + calleeSize <= kCallerCap;
}

} // namespace inlining
} // namespace idr

#endif // IDR_ANALYSIS_INLINE_H
