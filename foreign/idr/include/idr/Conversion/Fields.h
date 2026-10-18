// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What the owned stage settled about the cells it recycles, read before
// phase 2 of idr-lower forgets it.

#ifndef IDR_CONVERSION_FIELDS_H
#define IDR_CONVERSION_FIELDS_H

#include "idr/IR/IdrDialect.h"

#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/SmallVector.h"

#include <optional>

namespace idr::conversion {

class Fields {
public:
  // A recycle of the cell a take of its own constructor gave finds the
  // header in the cell already. A field an init gives back as the take gave
  // it is in the cell already too, with the reference the cell held all
  // along: the take moved it out without a count and the init moves it in
  // without one, so the owned stage counts nothing for it, and nothing need
  // be stored for it here. Each fact is the identity of two values of the
  // owned stage, which the conversion loses as it goes: it replaces each op
  // as it meets it, so by the time a recycle or an init is converted the
  // take that made its token is a test and some loads. So they are read
  // from every init before any function is converted; phase 1 moves the
  // ops it keeps, so each is still the op that was read.
  explicit Fields(mlir::Operation *program);

  // Whether `recycle`'s token is the take of a cell of the constructor it
  // recycles the cell for, whose header the cell holds already.
  bool sameConstructor(CellRecycleOp recycle) const;

  // For an init whose cell is such a recycle of an exclusive token, which
  // is the take's cell with no test: for each field, whether the cell holds
  // it already, because the init gives it back as the take gave it. None for
  // any other init, which stores every field: a recycle of a shared token
  // may give a fresh cell, and on its other path the fields the cell holds
  // are written again with the words it holds.
  std::optional<llvm::ArrayRef<bool>> kept(CellInitOp init) const;

private:
  llvm::DenseSet<mlir::Operation *> recycledSame;
  llvm::DenseMap<mlir::Operation *, llvm::SmallVector<bool>> keptFields;
};

} // namespace idr::conversion

#endif // IDR_CONVERSION_FIELDS_H
