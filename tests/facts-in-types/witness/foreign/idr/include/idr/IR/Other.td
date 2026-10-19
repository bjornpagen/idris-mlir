// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
def Idr_Other : Idr_Dialect {
  let discardableAttrs = (ins "::mlir::UnitAttr":$refusals);
}
