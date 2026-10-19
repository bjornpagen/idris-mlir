// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
def Idr_Planted : Idr_Op<"planted"> {
  let discardableAttrs = (ins "::mlir::UnitAttr":$planted);
}
