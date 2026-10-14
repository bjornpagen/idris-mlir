// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Whether a system with one more inequality has no integer point, which
// is what a proof asks of it. No rational point is no integer point, and
// MLIR's simplex decides that directly; what it leaves is branched on
// the fractional coordinates of its rational sample, below a
// coordinate's floor or above it, where there is no integer point
// between. Each branch is one more inequality on the same tableau,
// rolled back after. Past the budget of branches the system is left
// undecided, reported not empty, which only proves less; the exact
// searches of the Presburger library (a sample by generating functions,
// a lexicographic minimum) each have shapes of this system's size they
// do not finish on.

#include "idr/Transforms/InBounds.h"

#include "mlir/Analysis/Presburger/IntegerRelation.h"
#include "mlir/Analysis/Presburger/PresburgerSpace.h"
#include "mlir/Analysis/Presburger/Simplex.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;
using llvm::DynamicAPInt;
using mlir::presburger::IntegerPolyhedron;
using mlir::presburger::PresburgerSpace;

namespace idr::inbounds {

namespace {

bool integerEmpty(presburger::Simplex &simplex, unsigned vars, unsigned &budget) {
  if (simplex.isEmpty())
    return true;
  std::optional<SmallVector<presburger::Fraction>> sample = simplex.getRationalSample();
  if (!sample)
    return false;
  for (auto [i, value] : llvm::enumerate(*sample)) {
    if (value.den == 1)
      continue;
    if (budget == 0)
      return false;
    --budget;
    DynamicAPInt floor = value.num / value.den;
    if (value.num % value.den != 0 && value.num < 0)
      floor -= 1;
    auto branch = [&](const DynamicAPInt &coefficient, const DynamicAPInt &constant) {
      SmallVector<DynamicAPInt> row(vars + 1, DynamicAPInt(0));
      row[static_cast<unsigned>(i)] = coefficient;
      row[vars] = constant;
      simplex.addInequality(row);
    };
    unsigned snapshot = simplex.getSnapshotBasis();
    branch(DynamicAPInt(-1), floor);
    bool below = integerEmpty(simplex, vars, budget);
    simplex.rollback(snapshot);
    if (!below)
      return false;
    branch(DynamicAPInt(1), -(floor + DynamicAPInt(1)));
    bool above = integerEmpty(simplex, vars, budget);
    simplex.rollback(snapshot);
    return above;
  }
  return false;
}

} // namespace

bool System::emptyWith(const Linear &extra) const {
  IntegerPolyhedron polyhedron(PresburgerSpace::getSetSpace(count));
  auto dense = [&](const Linear &e) {
    SmallVector<DynamicAPInt> row(count + 1, DynamicAPInt(0));
    for (const auto &[column, c] : e.terms)
      row[column] += c;
    row[count] += e.constant;
    return row;
  };
  for (const Row &row : rows) {
    if (row.equality)
      polyhedron.addEquality(dense(row.e));
    else
      polyhedron.addInequality(dense(row.e));
  }
  presburger::Simplex simplex(polyhedron);
  simplex.addInequality(dense(extra));
  unsigned budget = 512;
  return integerEmpty(simplex, count, budget);
}

} // namespace idr::inbounds
