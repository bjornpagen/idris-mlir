// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What the lifetimes' rule of one function keeps as its walk goes: the
// lifetimes open where it stands, each at its depth, and the regions it is
// in, each with how many regions that run again enclose it. Outlives is
// dominance: a lifetime bound inside another's region is deeper, a
// function's lifetime parameters are at depth 0 and outlive every lifetime
// it binds, and two parameters outlive each other only as the signature's
// bounds say. A scoped value's lifetime is one hop from it
// (statedLifetime), so no rule follows a def-use chain, and whether a use
// runs again inside a lifetime is two counts compared, so none walks up.
#ifndef IDR_LIB_IR_LIFETIMES_RULES_H
#define IDR_LIB_IR_LIFETIMES_RULES_H

#include "idr/IR/Func.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Verify.h"

#include "mlir/IR/Operation.h"
#include "mlir/IR/Region.h"
#include "mlir/IR/Value.h"
#include "llvm/ADT/SmallVector.h"

#include <cstdint>
#include <optional>

namespace idr::verify {

// Whether nothing older on its stack may be put into inside a lifetime (a
// stack lifetime's discipline).
enum class Discipline : std::uint8_t { Free, Stack };

struct LifetimeRules::State {
  // A lifetime open where the walk stands, or a lifetime parameter: its
  // depth, its discipline, how many regions that run again enclose where
  // it was opened, and the region it is the extent of (none for a
  // parameter, which lives in its caller's memory).
  struct Open {
    mlir::Value lifetime;
    unsigned depth;
    Discipline discipline;
    unsigned again;
    mlir::Region *region;
  };

  // A region the walk is in: how many lifetimes were open when it was
  // entered, and how many regions that run again enclose it, it included.
  struct Level {
    size_t openAt;
    unsigned again;
  };

  explicit State(FuncOp fn) : fn(fn), entry(fn.getBody().front()), lives(fn.getLivesInAttr()) {}

  mlir::LogicalResult enter(mlir::Operation *op, mlir::Region &region);
  void leave();
  mlir::LogicalResult check(mlir::Operation &op);

  // The scope where the walk stands (Verify.cpp).
  unsigned depth() const { return open.empty() ? 0 : open.back().depth; }
  std::optional<unsigned> depthOf(mlir::Value lifetime) const;
  bool bounded(unsigned longer, unsigned shorter) const;
  bool outlives(mlir::Value a, mlir::Value b) const;
  std::optional<unsigned> stackDepth() const;
  bool livesAsLong(mlir::Value value, mlir::Value into) const;
  static bool states(mlir::Operation &op, mlir::Value lifetime);

  // The local rules of one op (Verify.cpp), and the frame-limited rule at
  // each use it makes of a lifetime (Proof.cpp).
  mlir::LogicalResult local(mlir::Operation &op);
  mlir::LogicalResult proof(mlir::Operation &user);
  std::optional<Open> recordOf(mlir::Value lifetime) const;
  static bool keptHere(mlir::Operation &user, mlir::Value lifetime);

  FuncOp fn;
  mlir::Block &entry;
  LivesInAttr lives;
  llvm::SmallVector<Open, 8> open;
  llvm::SmallVector<Level, 16> levels;
};

} // namespace idr::verify

#endif // IDR_LIB_IR_LIFETIMES_RULES_H
