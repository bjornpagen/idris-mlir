// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What the units of idr-rc-reuse share (lib/Transforms/Counting): one
// function's reuse, the sizes its sources give numbered densely, with the
// rebuilds lowered, the fusions and the pass (Reuse.cpp); the backward walk
// that measures the demand for each size (ReuseDemand.cpp); the forward
// walk that assigns tokens to sinks, carries them across a rejoin and frees
// the rest (ReuseAssign.cpp). The two walks meet the same points in reverse
// orders, so the demand passes from one to the other on one trail.
#ifndef IDR_TRANSFORMS_COUNTING_REUSE_H
#define IDR_TRANSFORMS_COUNTING_REUSE_H

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Quantities.h"
#include "idr/Transforms/Counting/Facts.h"

#include "mlir/IR/Operation.h"
#include "mlir/IR/Types.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <algorithm>
#include <cstdint>
#include <optional>
#include <vector>

namespace idr {
class Layouts;
} // namespace idr

namespace idr::counting::reuse {

// The most sinks of each size of the function's sources on some path ahead,
// one count per size, capped by how many sources of that size there are: a
// count that only grows over a finite set.
using Demand = llvm::SmallVector<std::uint32_t, 4>;

inline void raise(Demand &into, const Demand &other) {
  for (auto [a, b] : llvm::zip_equal(into, other))
    a = std::max(a, b);
}

// A token held on the forward walk's path: the size it may be recycled
// into, its place in the order of choice, and the handle that consumes it
// once.
struct Held {
  unsigned size;
  std::uint32_t order;
  Token token;
};

class Reuse {
public:
  Reuse(FuncOp fn, const Layouts &layouts) : fn(fn), layouts(layouts) {}

  void run();

  unsigned reuses = 0;
  unsigned freed = 0;
  unsigned fused = 0;
  unsigned rebuilds = 0;

private:
  // The sizes (Reuse.cpp).
  unsigned cellBytes(mlir::Type value) const;
  std::optional<unsigned> sourceBytes(mlir::Operation *op) const;
  std::optional<unsigned> indexOf(unsigned bytes) const;
  Demand none() const { return Demand(sizes.size(), 0); }

  // The demand (ReuseDemand.cpp).
  void demands();

  // The assignment (ReuseAssign.cpp).
  void assign();
  void freeAll(llvm::SmallVector<Held> &held, mlir::Operation *before);
  mlir::Operation *withTokenResults(mlir::Operation *op, llvm::ArrayRef<mlir::Type> tokens);

  // The rebuilds and the fusions (Reuse.cpp).
  void lowerRebuilds();
  void fuse();

  FuncOp fn;
  const Layouts &layouts;
  // The sizes the function's sources give, numbered densely.
  llvm::SmallVector<unsigned, 4> sizes;
  // What the backward walk measured, in the order it met each point: after
  // each region op, after each source, at each region's head.
  std::vector<Demand> trail;
  std::uint32_t nextOrder = 0;
};

} // namespace idr::counting::reuse

#endif // IDR_TRANSFORMS_COUNTING_REUSE_H
