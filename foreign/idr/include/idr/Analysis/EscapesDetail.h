// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What the units of the escape analysis share, and no other unit reads:
// lib/Analysis/Escapes.cpp, which solves, and EscapesCycles.cpp, which
// reads the answers beside the cycles and the loops. The state each value
// holds in the solve, and how it is read.
#ifndef IDR_ANALYSIS_ESCAPESDETAIL_H
#define IDR_ANALYSIS_ESCAPESDETAIL_H

#include "idr/Analysis/Escapes.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/Analysis/DataFlow/SparseAnalysis.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/Support/raw_ostream.h"

namespace idr::detail::escapes {

using mlir::dataflow::Lattice;

// Where the uses one way of standing for a value reach. `escapes`: a use
// that lets it go. `tailCalled`: a call in tail position (modulo a
// context, which idr-trmc makes a loop) of a function on its
// function's cycle, which ends the frame. `loops`: the loops whose
// terminators forward it to the next iteration or out. The last two
// are about the frame of the value's own function, so they never cross a
// call: a cell passed to a callee is in the caller's frame, which outlives
// whatever the callee does with its own frame and loops. Only `escapes`
// does.
struct Reach {
  bool escapes = false;
  bool tailCalled = false;
  // Sorted, each once: two states compare by what they hold.
  llvm::SmallVector<mlir::Operation *, 1> loops;

  void add(const Reach &other) {
    escapes |= other.escapes;
    tailCalled |= other.tailCalled;
    for (mlir::Operation *loop : other.loops)
      if (auto at = llvm::lower_bound(loops, loop); at == loops.end() || *at != loop)
        loops.insert(at, loop);
  }
  bool operator==(const Reach &) const = default;
};

// The state of a value: how its own address reaches (shallow) and how
// everything reachable from it does (deep). Nothing reaches anywhere until
// a use says so, and the solve only adds, so it ends with the least
// solution, whose bottom is the default state.
struct Escape {
  Reach shallow;
  Reach deep;

  static Escape join(const Escape &lhs, const Escape &rhs) {
    Escape out = lhs;
    out.shallow.add(rhs.shallow);
    out.deep.add(rhs.deep);
    // Everything reachable from a value includes its own address.
    out.deep.add(out.shallow);
    return out;
  }
  // A backward analysis meets what each use says; here that is the union.
  static Escape meet(const Escape &lhs, const Escape &rhs) { return join(lhs, rhs); }
  bool operator==(const Escape &) const = default;

  void print(llvm::raw_ostream &os) const {
    auto reach = [&](const Reach &r) {
      os << (r.escapes ? "escapes" : "-") << (r.tailCalled ? " tail" : "") << " loops "
         << r.loops.size();
    };
    os << "shallow ";
    reach(shallow);
    os << ", deep ";
    reach(deep);
  }
};

class EscapeLattice : public Lattice<Escape> {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(EscapeLattice)
  using Lattice::Lattice;
};

// The values that hold an address of their own: a box, whose reference is
// its cell's address, and a cell. A type as it is at runtime: a grade has
// no runtime form.
inline bool holdsOwnAddress(mlir::Type type) {
  return llvm::isa<BoxType, CellType>(unrestricted(type));
}

// The values whose addresses the analysis follows: those that hold one of
// their own, and unboxed sums, whose fields may hold boxes.
inline bool holdsCells(mlir::Type type) {
  return llvm::isa<BoxType, DataType, CellType>(unrestricted(type));
}

// The part of `state` that stands for `value`'s own address: the shallow
// part where it holds one, and a sum's only part, the deep one.
inline const Reach &own(mlir::Value value, const Escape &state) {
  return holdsOwnAddress(value.getType()) ? state.shallow : state.deep;
}

} // namespace idr::detail::escapes

#endif // IDR_ANALYSIS_ESCAPESDETAIL_H
