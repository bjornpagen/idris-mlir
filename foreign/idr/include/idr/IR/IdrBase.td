// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The idr dialect and the enums and classes every other part of its ODS
// names: the halves of a grade, the kinds of sum a data type is, the rules a
// refusal of a program names and what kind of program each refuses, the
// conditions a guard checks and the roles of a sum's constructors, and what
// an op says once beside itself for idris-mlir-tblgen to generate from: its
// runtime function and its guards.

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
    // The types, registered where their storage is complete (lib/IR/Types.cpp),
    // and the value facts of the builtin types a value may have
    // (lib/IR/ValueFacts.cpp), which registering the types attaches.
    void registerTypes();
    void registerValueFacts();

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
// base's list, which the string ops walk and build; one of mlir-linear's,
// rebuilt in place and held alone, as the registry names it; a sum
// idr-defunctionalize makes of closures, a constructor per label whose
// fields are its captures; or one it makes of a lazy type, its labels and
// the states a force writes a cell into. Which constructor plays which part
// is each constructor's role (CtorRole, IdrAttrs.td), never its position.
def Idr_SumKind : I32EnumAttr<"SumKind", "what sum a data type is", [
    I32EnumAttrCase<"Plain", 0, "plain">, I32EnumAttrCase<"BaseList", 1, "list">,
    I32EnumAttrCase<"InPlace", 2, "in_place">, I32EnumAttrCase<"Closures", 3, "closures">,
    I32EnumAttrCase<"Memo", 4, "memo">]> {
  let cppNamespace = "::idr";
  let genSpecializedAttr = 0;
}

// The part a constructor plays in its sum, said by the constructor itself,
// so that no reader finds one by its position or its name: an Idris
// constructor; base list's nil, and its cons of an element and the list; a
// label of a closure or a memo sum, whose function the constructor names;
// and a memo cell's states, `running` while its force runs, `forced` with
// the value after. A plain sum's constructors are plain, a list is one nil
// and one cons, a closure sum's are labels, and a memo sum's are labels and
// one of each state (lib/IR/Types.cpp). It is the data type's, and every
// constructor attribute and op names a constructor by its tag, so it is
// here, before both. No case is named as anything in Idris's prelude is
// (its list's Nil and Cons): idris-mlir-tblgen writes the cases into Idris
// as they are.
def Idr_CtorRole : I32EnumAttr<"CtorRole", "the part a constructor plays in its sum", [
    I32EnumAttrCase<"Plain", 0, "plain">, I32EnumAttrCase<"ListNil", 1, "nil">,
    I32EnumAttrCase<"ListCons", 2, "cons">, I32EnumAttrCase<"Label", 3, "label">,
    I32EnumAttrCase<"Running", 4, "running">, I32EnumAttrCase<"Forced", 5, "forced">]> {
  let cppNamespace = "::idr";
  let genSpecializedAttr = 0;
}

//===----------------------------------------------------------------------===//
// Refusals
//===----------------------------------------------------------------------===//

// The two kinds of program a refusal names, and the only two: a megamorphic
// construct, whose choices at a site (the types, instances, implementations
// or shapes it can meet) no compile-time analysis bounds; and one outside
// the language this compiler compiles, as %foreign, threads, finalizers and
// raw pointers are, or one a total analysis proves the program cannot meet
// (a reference knot counting would never free, an in-place promise shared).
// No limit of the compiler's is a third kind: a limit is lifted by a
// representation, never refused.
def Idr_Megamorphic : I32EnumAttrCase<"Megamorphic", 0, "megamorphic">;
def Idr_OutsideLanguage : I32EnumAttrCase<"OutsideLanguage", 1, "outside the language">;
def Idr_RuleCategory : I32EnumAttr<"RuleCategory", "the kind of program a refusal names", [
    Idr_Megamorphic, Idr_OutsideLanguage]> {
  let cppNamespace = "::idr";
  let genSpecializedAttr = 0;
}

// A rule, with the phrase it is shown as and the kind of program it
// refuses, which idris-mlir-tblgen writes into the Idris side and into the
// tests' rule list. Every case of Idr_Rule is one of these.
class Idr_RuleCase<string symbol, int value, string phrase, I32EnumAttrCase kind>
    : I32EnumAttrCase<symbol, value, phrase> {
  I32EnumAttrCase category = kind;
}

// The rules a refusal of a program names, each with the phrase it is shown
// as, `unsupported (<phrase>): ...`. The frontend's and the pipeline's are
// one list: C++ reads it from here, and idris-mlir-tblgen writes the Idris
// side's `Rule` from it. A phrase of two words is no keyword, so the
// attribute writes it as a string. A value, once given, is never given to
// another rule.
def Idr_Rule : I32EnumAttr<"Rule", "the rule a refusal of a program names", [
    Idr_RuleCase<"ProgramShape", 0, "program", Idr_OutsideLanguage>,
    Idr_RuleCase<"TrustedLibrary", 1, "library", Idr_OutsideLanguage>,
    Idr_RuleCase<"WorldUse", 2, "world", Idr_OutsideLanguage>,
    Idr_RuleCase<"IOPrimitive", 3, "io primitive", Idr_OutsideLanguage>,
    // A type in a runtime position: chosen by a runtime value.
    Idr_RuleCase<"ValueType", 4, "type", Idr_Megamorphic>,
    Idr_RuleCase<"DependentField", 5, "dependent field", Idr_Megamorphic>,
    Idr_RuleCase<"DictionaryField", 6, "dictionary field", Idr_Megamorphic>,
    Idr_RuleCase<"DataType", 7, "data type", Idr_OutsideLanguage>,
    Idr_RuleCase<"DefinitionShape", 8, "definition", Idr_OutsideLanguage>,
    Idr_RuleCase<"Match", 9, "match", Idr_OutsideLanguage>,
    Idr_RuleCase<"StaticArgument", 10, "static argument", Idr_Megamorphic>,
    Idr_RuleCase<"Polymorphism", 11, "polymorphism", Idr_Megamorphic>,
    Idr_RuleCase<"Primitive", 13, "primitive", Idr_OutsideLanguage>,
    Idr_RuleCase<"StringPrimitive", 14, "string primitive", Idr_OutsideLanguage>,
    Idr_RuleCase<"RuntimeClosure", 15, "runtime closure", Idr_Megamorphic>,
    Idr_RuleCase<"EscapeHatch", 16, "escape hatch", Idr_OutsideLanguage>,
    Idr_RuleCase<"UserPragma", 17, "pragma", Idr_OutsideLanguage>,
    // Threads (`fork`, `threadWait`): no scheduler, and shared mutable
    // state the counting heap does not have.
    Idr_RuleCase<"Threads", 18, "threads", Idr_OutsideLanguage>,
    // A collector finalizer (`onCollect`). Release is the counting walk;
    // nothing runs at collection.
    Idr_RuleCase<"Finalizer", 19, "finalizer", Idr_OutsideLanguage>,
    // Raw memory (`System.FFI`'s `malloc` and its kin). A pointer of base
    // is a handle of the runtime's, and references the compiler keeps are
    // heap values it accounts for.
    Idr_RuleCase<"RawPointer", 20, "raw pointer", Idr_OutsideLanguage>,
    // A signal handler, which runs an effect at a time the world does not
    // name.
    Idr_RuleCase<"Signal", 21, "signal", Idr_OutsideLanguage>,
    // Process creation (`system`, `popen`), outside the language for now.
    Idr_RuleCase<"Process", 22, "process", Idr_OutsideLanguage>,
    Idr_RuleCase<"CompiledModule", 23, "compiled module", Idr_OutsideLanguage>,
    Idr_RuleCase<"IdentityHook", 24, "identity hook", Idr_OutsideLanguage>,
    Idr_RuleCase<"HookShape", 25, "hook", Idr_OutsideLanguage>,
    // A name Idris has deprecated. The message names its replacement.
    Idr_RuleCase<"Deprecated", 26, "deprecated", Idr_OutsideLanguage>,
    // A value passed shared where the in-place promise needs it alone,
    // which exclusivity, a total analysis, cannot meet.
    Idr_RuleCase<"Uniqueness", 28, "uniqueness", Idr_OutsideLanguage>,
    // An array that can reach itself, which counting cannot free: a
    // question of the module's types, answered whole.
    Idr_RuleCase<"Cycle", 29, "cycle", Idr_OutsideLanguage>,
    // A runtime the compiler cannot link as it is.
    Idr_RuleCase<"Runtime", 30, "runtime", Idr_OutsideLanguage>]> {
  let cppNamespace = "::idr";
  let genSpecializedAttr = 0;
  let parameterPrinter = "$_printer.printKeywordOrString(::idr::stringifyRule($_self))";
}

//===----------------------------------------------------------------------===//
// Guards
//===----------------------------------------------------------------------===//

// The condition a guard checks (idr.check.*), spelled as its op is named.
// No case is named as anything in Idris's prelude is: idris-mlir-tblgen
// writes the cases into Idris as they are.
def Idr_CheckKind : I32EnumAttr<"CheckKind", "the condition a guard checks", [
    I32EnumAttrCase<"Nonzero", 0, "nonzero">, I32EnumAttrCase<"InBounds", 1, "in_bounds">,
    I32EnumAttrCase<"Nonempty", 2, "nonempty">,
    I32EnumAttrCase<"Finite", 4, "finite">, I32EnumAttrCase<"InRange", 5, "range">]> {
  let cppNamespace = "::idr";
  let genSpecializedAttr = 0;
}

//===----------------------------------------------------------------------===//
// What an op says once, for idris-mlir-tblgen
//===----------------------------------------------------------------------===//

// A primitive op that lowers to a call of the runtime's C function
// `symbol`. The function's parameters and result are the words of the op's
// operand and result types, and it does not return when the op carries
// that trait: idris-mlir-tblgen writes the C prototypes the runtime
// includes and the table the lowering and the folders read, so a mismatch
// between this and the runtime is a compile error of the runtime. Every op
// with it has the C++ trait ::idr::CallsRuntime.
class Idr_Runtime<string cSymbol> : NativeOpTrait<"CallsRuntime"> {
  let cppNamespace = "::idr";
  string symbol = cSymbol;
}

// A partial op's guard: the operand named `guardedOperand` must meet the
// condition `checkKind` (a case of Idr_CheckKind) or the program crashes
// with the message `crashCause`. An op guarded on several operands carries
// one of these per operand. idris-mlir-tblgen writes the guards the
// frontend builds before each op from these; no C++ is generated from one.
class Idr_Guarded<string guardedOperand, string checkKind, string crashCause>
    : GenInternalOpTrait<"Guarded"> {
  string operand = guardedOperand;
  string kind = checkKind;
  string cause = crashCause;
}

#endif // IDR_BASE
