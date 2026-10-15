// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The idr dialect and the enums every other part of its ODS names: the
// halves of a grade, the kinds of sum a data type is, and the rules a
// refusal of a program names.

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
    // The types, registered where their storage is complete (lib/IR/Types.cpp).
    void registerTypes();

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
  // No idr.* attribute on an op or an argument: every fact is an op's own
  // property or a type, where no pass drops it silently.
  let hasOperationAttrVerify = 1;
  let hasRegionArgAttrVerify = 1;
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

//===----------------------------------------------------------------------===//
// Data types
//===----------------------------------------------------------------------===//

// What sum a data type is, said once in its body: an Idris data type;
// base's list, nil and then cons, which the string ops walk and build; one
// of mlir-linear's, rebuilt in place and held alone, as the registry names
// it; a sum idr-defunctionalize makes of closures, a constructor per label
// whose fields are its captures; or one it makes of a lazy type, its labels
// and then the states a force writes a cell into, `running` and `forced`.
def Idr_SumKind : I32EnumAttr<"SumKind", "what sum a data type is", [
    I32EnumAttrCase<"Plain", 0, "plain">, I32EnumAttrCase<"BaseList", 1, "list">,
    I32EnumAttrCase<"InPlace", 2, "in_place">, I32EnumAttrCase<"Closures", 3, "closures">,
    I32EnumAttrCase<"Memo", 4, "memo">]> {
  let cppNamespace = "::idr";
  let genSpecializedAttr = 0;
}

//===----------------------------------------------------------------------===//
// Refusals
//===----------------------------------------------------------------------===//

// The rules a refusal of a program names, each with the phrase it is shown
// as, `unsupported (<phrase>): ...`. The frontend's and the pipeline's are
// one list: C++ reads it from here, and idris-mlir-tblgen writes the Idris
// side's `Rule` from it. A phrase of two words is no keyword, so the
// attribute writes it as a string.
def Idr_Rule : I32EnumAttr<"Rule", "the rule a refusal of a program names", [
    I32EnumAttrCase<"ProgramShape", 0, "program">,
    I32EnumAttrCase<"TrustedLibrary", 1, "library">,
    I32EnumAttrCase<"WorldUse", 2, "world">,
    I32EnumAttrCase<"IOPrimitive", 3, "io primitive">,
    I32EnumAttrCase<"ValueType", 4, "type">,
    I32EnumAttrCase<"DependentField", 5, "dependent field">,
    I32EnumAttrCase<"DictionaryField", 6, "dictionary field">,
    I32EnumAttrCase<"DataType", 7, "data type">,
    I32EnumAttrCase<"DefinitionShape", 8, "definition">,
    I32EnumAttrCase<"Match", 9, "match">,
    I32EnumAttrCase<"StaticArgument", 10, "static argument">,
    I32EnumAttrCase<"Polymorphism", 11, "polymorphism">,
    I32EnumAttrCase<"Laziness", 12, "laziness">,
    I32EnumAttrCase<"Primitive", 13, "primitive">,
    I32EnumAttrCase<"StringPrimitive", 14, "string primitive">,
    I32EnumAttrCase<"RuntimeClosure", 15, "runtime closure">,
    I32EnumAttrCase<"EscapeHatch", 16, "escape hatch">,
    I32EnumAttrCase<"UserPragma", 17, "pragma">,
    // Threads (`fork`, `threadWait`): no scheduler, and shared mutable
    // state the counting heap does not have.
    I32EnumAttrCase<"Threads", 18, "threads">,
    // A collector finalizer (`onCollect`). Release is the counting walk;
    // nothing runs at collection.
    I32EnumAttrCase<"Finalizer", 19, "finalizer">,
    // Raw memory (`System.FFI`'s `malloc` and its kin). A pointer of base
    // is a handle of the runtime's, and references the compiler keeps are
    // heap values it accounts for.
    I32EnumAttrCase<"RawPointer", 20, "raw pointer">,
    // A signal handler, which runs an effect at a time the world does not
    // name.
    I32EnumAttrCase<"Signal", 21, "signal">,
    // Process creation (`system`, `popen`), outside the language for now.
    I32EnumAttrCase<"Process", 22, "process">,
    I32EnumAttrCase<"CompiledModule", 23, "compiled module">,
    I32EnumAttrCase<"IdentityHook", 24, "identity hook">,
    I32EnumAttrCase<"HookShape", 25, "hook">,
    // A name Idris has deprecated. The message names its replacement.
    I32EnumAttrCase<"Deprecated", 26, "deprecated">,
    // A cell the runtime's header cannot describe.
    I32EnumAttrCase<"Layout", 27, "layout">,
    // A value passed shared where the in-place promise needs it alone.
    I32EnumAttrCase<"Uniqueness", 28, "uniqueness">,
    // An array that can reach itself, which counting cannot free.
    I32EnumAttrCase<"Cycle", 29, "cycle">,
    // A runtime the compiler cannot link as it is.
    I32EnumAttrCase<"Runtime", 30, "runtime">]> {
  let cppNamespace = "::idr";
  let genSpecializedAttr = 0;
  let parameterPrinter = "$_printer.printKeywordOrString(::idr::stringifyRule($_self))";
}

#endif // IDR_BASE
