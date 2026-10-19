// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
def Idr_Beside : Idr_Dialect {
  let discardableAttrs = (ins "::mlir::ArrayAttr":$refusals, "::mlir::UnitAttr":$hot);
}
