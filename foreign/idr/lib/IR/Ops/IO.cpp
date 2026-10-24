// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What the guards need by hand: the operand a guard guards, its first,
// which GuardOpInterface gives.

#include "idr/IR/IdrDialect.h"

using namespace mlir;
using namespace idr;

Value idr::guardedOperand(Operation *guard) { return guard->getOperand(0); }
