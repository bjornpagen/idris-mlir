// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// let discardableAttrs = (ins "::mlir::UnitAttr":$planted); a comment declares nothing
def Idr_Allowed : Idr_Dialect {
  let discardableAttrs = (ins "::mlir::ArrayAttr":$refusals);
}
def Idr_None : Idr_Dialect {
  let discardableAttrs = (ins);
}
def Idr_Inherent : Idr_Op<"inherent"> {
  let arguments = (ins UnitAttr:$discardableAttrsSeen);
}
