// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The idr ops, as TableGen defines them from the specification. An op of
// inline arithmetic folds, infers its ranges and expands through its trait
// (Numeric/Trait.h), and an op whose meaning is a runtime function folds
// through RuntimeFolds (Fold.h), so no op's arithmetic is written here.
// Every hook an op declares by hand, a custom directive among them, is
// defined in the unit of its family.

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/DialectImplementation.h"
#include "mlir/IR/OpImplementation.h"

using namespace mlir;
using namespace idr;

#include "idr/IR/IdrInterfaces.cpp.inc"

#define GET_OP_CLASSES
#include "idr/IR/IdrOps.cpp.inc"
