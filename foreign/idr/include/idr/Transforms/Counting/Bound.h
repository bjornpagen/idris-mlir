// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A function's frame bound and the points it rests on (Bound.cpp): what an
// active call of it holds that it no longer needs, the emptied cells of its
// reuse tokens and what each owner it lends and needs no more after the
// loan reaches, each sized by its type on the target. One walk gives both
// readers what they read: idr-rc-reuse keeps the bound on the function, the
// most held at any op that may acquire memory; the lowering tells the
// checked runtime's account each point where what is held rises or falls,
// so the account follows the rule the bound was computed by and states no
// rule of its own.
#ifndef IDR_TRANSFORMS_COUNTING_BOUND_H
#define IDR_TRANSFORMS_COUNTING_BOUND_H

#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Counting/Facts.h"

#include "llvm/ADT/SmallVector.h"

#include <cstdint>

namespace idr {
class Layouts;
} // namespace idr

namespace idr::counting {

// Whether what a call holds that it no longer needs grows or shrinks at a
// point.
enum class Direction : std::uint8_t { Rises, Falls };

// A point where what an active call holds that it no longer needs changes,
// right before the op `where` names, by `bytes`:
//   - a token's cell rises where the token is made, past the op that makes
//     it or at the start of the region that binds it, and falls before the
//     op that consumes it (a recycle, a free). A token that may be null
//     counts at its cell's size at both ends, as the bound counts it, so
//     what the account holds is never below what the run holds and needs
//     no test of its own;
//   - a lent owner's reach rises at the start of its loan's region and
//     falls before each use that gives it up.
// A token moved on unchanged (into a region, out of one, or through an op
// that gives it back) stays held and has no point.
struct HoldPoint {
  Where where;
  Direction direction;
  std::uint64_t bytes;
};

// The function's frame bound, as reuse leaves it: the most bytes it holds
// dead at any op that may acquire memory. In the width the function's
// `frame_bound` holds it, a signed word, which every count of bytes of a
// 64-bit address space fits, never negative.
std::int64_t frameBound(FuncOp fn, const Layouts &layouts);

// Every point where what the function holds dead rises or falls, on the
// function as it stands, in the order the walk meets them; points at one
// position keep that order.
llvm::SmallVector<HoldPoint> holdPoints(FuncOp fn, const Layouts &layouts);

} // namespace idr::counting

#endif // IDR_TRANSFORMS_COUNTING_BOUND_H
