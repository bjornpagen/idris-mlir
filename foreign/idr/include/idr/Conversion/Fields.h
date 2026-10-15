// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What the owned stage settled about the fields of the ops that count
// references, read before phase 2 of idr-lower forgets it.

#ifndef IDR_CONVERSION_FIELDS_H
#define IDR_CONVERSION_FIELDS_H

#include "idr/IR/IdrDialect.h"

#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallVector.h"

namespace idr::conversion {

class Fields {
public:
  // A field a reuse gives back as its token's take gave it is in the cell
  // already, with the reference the cell held all along: the take moved it
  // out without a count and the reuse moves it in without one, so the owned
  // stage counts nothing for it, and nothing need be stored for it here.
  // The fact is the identity of two values of the owned stage, which the
  // conversion loses as it goes: it replaces each op as it meets it, so by
  // the time a reuse is converted the take that made its token is a test
  // and some loads. So it is read from every reuse after phase 1, before
  // the conversion starts.
  explicit Fields(mlir::Operation *program);

  // For a reuse of the constructor its token's take took apart: for each
  // field, whether the cell holds it already, because the reuse gives it
  // back as the take gave it. Empty for a reuse of another constructor,
  // whose cell holds none of its fields, and a new header.
  llvm::ArrayRef<bool> kept(ReuseOp reuse) const;

private:
  llvm::DenseMap<mlir::Operation *, llvm::SmallVector<bool>> keptFields;
};

} // namespace idr::conversion

#endif // IDR_CONVERSION_FIELDS_H
