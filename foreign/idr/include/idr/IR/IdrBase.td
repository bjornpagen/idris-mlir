// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The idr dialect and the enums every other part of its ODS names: the
// halves of a grade.

#ifndef IDR_BASE
#define IDR_BASE

include "mlir/IR/OpBase.td"
include "mlir/IR/OpAsmInterface.td"
include "mlir/IR/AttrTypeBase.td"
include "mlir/IR/EnumAttr.td"
include "mlir/IR/SymbolInterfaces.td"
include "mlir/IR/BuiltinAttributes.td"
include "mlir/IR/BuiltinTypeInterfaces.td"
include "mlir/Interfaces/CallInterfaces.td"
include "mlir/Interfaces/ControlFlowInterfaces.td"
include "mlir/Interfaces/FunctionInterfaces.td"
include "mlir/Interfaces/InferIntRangeInterface.td"
include "mlir/Interfaces/InferTypeOpInterface.td"
include "mlir/Interfaces/SideEffectInterfaces.td"

def Idr_Dialect : Dialect {
  let name = "idr";
  let cppNamespace = "::idr";
  let summary = "Monomorphic Idris programs: data, closures, matches, strings and bigs";
  // The dialect reads and writes its types: the common grades have
  // spellings, one table of them over the generated syntax (lib/IR/Dialect.cpp).
  let useDefaultTypePrinterParser = 0;
  let extraClassDeclaration = [{
    ::mlir::Type parseType(::mlir::DialectAsmParser &parser) const override;
    void printType(::mlir::Type type, ::mlir::DialectAsmPrinter &printer) const override;

    // The runtime cells the folders left live on this context, summed over
    // every thread that folded. Per context, because a context is one
    // compilation's state and its folds may run on several threads. The add
    // is atomic, and a sum does not depend on which thread folded.
    void countFoldLeak(int64_t cells) { foldLeak.fetch_add(cells, std::memory_order_relaxed); }
    int64_t foldLeakCount() const { return foldLeak.load(std::memory_order_relaxed); }

  private:
    std::atomic<int64_t> foldLeak{0};
  }];
  let useDefaultAttributePrinterParser = 1;
  let hasConstantMaterializer = 1;
  // Upstream's patterns on other dialects' ops over this dialect's values:
  // the dimension of an array (lib/IR/Dialect.cpp).
  let hasCanonicalizer = 1;
  // The module's rules under `program`, the place of `stack`, and no other
  // idr.* attribute on an op or an argument.
  let hasOperationAttrVerify = 1;
  let hasRegionArgAttrVerify = 1;
  // The dialect's two discardable attributes: the module is a whole
  // program (`program`, on the module), and idr-stack's box whose cell never
  // leaves its frame (`stack`, on an idr.con), each read and written only
  // through its generated helper. A function's facts are idr.func's own
  // attributes, and a fact Idris proved is never one of these: it is a type.
  let discardableAttrs = (ins "::mlir::UnitAttr":$program, "::mlir::UnitAttr":$stack);
  // Constants of scalars, regions ending in ub.unreachable, the branch the
  // inliner's block form of idr.return becomes, and the layouts of cells,
  // whose sizes the owned stage checks, which are LLVM's. No idr op or
  // pattern makes a func op.
  let dependentDialects = ["::mlir::arith::ArithDialect", "::mlir::cf::ControlFlowDialect",
                           "::mlir::ub::UBDialect", "::mlir::LLVM::LLVMDialect"];
}

//===----------------------------------------------------------------------===//
// Grades
//===----------------------------------------------------------------------===//

// A grade's halves (idr::Grade), enums so that their spellings are said
// once: read by the generated parser, written by the generated printers in
// C++ and in Idris. The quantity is spelled in words: an enum parameter is
// read as a keyword, which `0` and `1` are not.
// A value of quantity zero has no runtime representation, so no grade
// spells one.
def Idr_Quantity : I32EnumAttr<"Quantity", "the number of uses Idris proved of a value", [
    I32EnumAttrCase<"One", 1, "one">, I32EnumAttrCase<"Many", 2, "many">]> {
  let cppNamespace = "::idr";
  let genSpecializedAttr = 0;
}

def Idr_Permission : I32EnumAttr<"Permission", "what a value owns", [
    I32EnumAttrCase<"Plain", 0, "plain">, I32EnumAttrCase<"Borrow", 1, "borrow">,
    I32EnumAttrCase<"Own", 2, "own">, I32EnumAttrCase<"Excl", 3, "excl">]> {
  let cppNamespace = "::idr";
  let genSpecializedAttr = 0;
}

#endif // IDR_BASE
