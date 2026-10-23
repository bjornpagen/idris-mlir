// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The lifetimes open where the lifetimes' walk of a function stands, which
// the walk keeps as it enters and leaves regions and each op's own rule
// reads (LifetimeUseOpInterface::verifyLifetimeUse): the function's
// lifetime parameters at depth 0, and each lifetime opened around the op one
// deeper than everything open where it was opened. Outlives is dominance: a
// lifetime bound inside another's region is deeper, a parameter outlives
// every lifetime its function binds, and two parameters outlive each other
// only as the signature's bounds say. A scoped value's lifetime is one hop
// from it (statedLifetime), so no question here follows a def-use chain.
#ifndef IDR_IR_LIFETIMES_OPEN_H
#define IDR_IR_LIFETIMES_OPEN_H

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Block.h"
#include "mlir/IR/Region.h"
#include "mlir/IR/Value.h"
#include "llvm/ADT/SmallVector.h"

#include <cstddef>
#include <cstdint>
#include <optional>

namespace idr {

class OpenLifetimes {
public:
  // Whether nothing older on its stack may be put into inside a lifetime (a
  // stack lifetime's discipline).
  enum class Discipline : std::uint8_t { Free, Stack };

  // A lifetime open where the walk stands, or a lifetime parameter: its
  // depth, its discipline, how many regions that run again enclose where it
  // was opened, and the region it is the extent of (none for a parameter,
  // which lives in its caller's memory).
  struct Open {
    mlir::Value lifetime;
    unsigned depth;
    Discipline discipline;
    unsigned again;
    mlir::Region *region;
  };

  explicit OpenLifetimes(FuncOp fn)
      : entry(fn.getBody().front()), lives(fn.getLivesInAttr()) {}

  // The depth of a lifetime in scope, its extent's: a parameter's 0; none
  // for a lifetime not open here.
  std::optional<unsigned> depthOf(mlir::Value lifetime) const;
  // Whether `a` lives at least as long as `b`, both in scope.
  bool outlives(mlir::Value a, mlir::Value b) const;
  // Whether `value` lives at least as long as `into`, the lifetime the place
  // it goes to names: a scoped value by its stated lifetime; any other value
  // outlives every lifetime, or its own count frees it.
  bool livesAsLong(mlir::Value value, mlir::Value into) const;
  // The lifetime parameter the function's signature names for its result
  // `index`; null where it names none.
  mlir::Value resultLifetime(unsigned index) const;
  // The innermost open stack lifetime's depth, if one is open.
  std::optional<unsigned> stackDepth() const;
  // The lifetime itself as held: open where the walk stands, or a parameter
  // of the function, whose extent is its caller's. A lifetime derived from
  // another by a view's cast is none.
  std::optional<Open> recordOf(mlir::Value lifetime) const;

  // What the walk changes as it goes: the depth of the innermost lifetime
  // open, how many are open, one more opened, and those opened since `size`
  // closed as the walk leaves their region.
  unsigned depth() const { return held.empty() ? 0 : held.back().depth; }
  std::size_t size() const { return held.size(); }
  void push(const Open &opened) { held.push_back(opened); }
  void popTo(std::size_t size) { held.truncate(size); }

private:
  // Whether the parameter at `longer` lives at least as long as the one at
  // `shorter`, by the bounds the signature states.
  bool bounded(unsigned longer, unsigned shorter) const;

  mlir::Block &entry;
  LivesInAttr lives;
  llvm::SmallVector<Open, 8> held;
};

} // namespace idr

#endif // IDR_IR_LIFETIMES_OPEN_H
