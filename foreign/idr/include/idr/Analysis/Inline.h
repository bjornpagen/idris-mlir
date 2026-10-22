// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The inliner's budget: MLton's numbers, which weigh whether a callee's
// body is worth copying into its callers, and the most a caller may hold.
// A spent budget keeps a call and never refuses a program. The verdict
// that reads them is the inliner's own, decided on the final program graph
// where every call site is counted.
#ifndef IDR_ANALYSIS_INLINE_H
#define IDR_ANALYSIS_INLINE_H

#include <cstdint>

namespace idr::inlining {

// MLton's numbers, in ops and call sites: a leaf, a body that calls
// nothing, of at most kLeafSize ops always inlines; any other body when
// (calls - 1) * (size - kSmall) <= kProduct.
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

} // namespace idr::inlining

#endif // IDR_ANALYSIS_INLINE_H
