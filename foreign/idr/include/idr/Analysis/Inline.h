// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Whether a call is inlined: MLton's per-function rule, decided once on the
// callee's final body and read at each call, and the most a caller may
// hold. The rule never refuses anything, it answers inline or keep.
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

// What a call reads of a final callee: the verdict, and the size its body
// adds to the caller.
struct Facts {
  // inlineSize of the final body.
  int64_t size = 0;
  // Whether a call of the function inlines it.
  bool inlines = false;
};

// MLton's rule, decided once on the final body of `fn`: never a function on
// a cycle of calls, which is `shared` (a member of a final component of two
// or more) or a body that calls `fn` itself, since its original could never
// go; never one the frontend marked `no_inline`; always a leaf, a body with
// no idr.call, of at most kLeafSize ops; any other when
// (calls - 1) * (size - kSmall) <= kProduct. `calls` is the number of the
// program's idr.call sites naming `fn` when idr-optimize began, 1 for a
// specialization node, one per request. A specialization node of a
// recursive function on static data is `shared`; one whose key fixes
// only closures of labels outside the recursion applies them, and is not
// (optimize::Node::stepOfRecursion).
Facts factsOf(idr::FuncOp fn, unsigned calls, bool shared);

// Whether a caller of `callerSize` ops stays at or under kCallerCap with
// the call replaced by a body of `calleeSize` ops. A callee is one block,
// whose return inlining drops; `calleeSize` counts it all the same.
inline bool fitsCap(int64_t callerSize, int64_t calleeSize) {
  return callerSize - 1 + calleeSize <= kCallerCap;
}

} // namespace inlining
} // namespace idr

#endif // IDR_ANALYSIS_INLINE_H
