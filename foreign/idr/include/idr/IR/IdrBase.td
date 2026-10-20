// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The idr dialect and the enums and classes every other part of its ODS
// names: the halves of a grade, the kinds of sum a data type is, the rules a
// refusal of a program names and what kind of program each refuses, the
// conditions a guard checks and the roles of a sum's constructors, what an
// op says once beside itself for idris-mlir-tblgen to generate from (its
// runtime function, its guards, the C ABI's word of a type it takes), and
// the constraints the op families share.

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
  // Constants of scalars, regions ending in ub.unreachable, and the layouts
  // of cells, whose sizes the owned stage checks, which are LLVM's. No idr
  // op or pattern makes a func op.
  let dependentDialects = ["::mlir::arith::ArithDialect", "::mlir::ub::UBDialect",
                           "::mlir::LLVM::LLVMDialect"];
  // The frontend's report to the driver: the refusals it found, which the
  // driver re-emits and no pass reads (lib/IR/Verify/Attributes.cpp).
  let discardableAttrs = (ins "::mlir::ArrayAttr":$refusals);
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

// How long what a value reaches lives, the grade's third part, shortest
// last: static data, which no count reaches and which lives as long as the
// program; on the heap, as long as a reference to it does; or in the frame
// of the function that holds the value, which dies with the frame or with
// the loop iteration that made it. Static is a view's lifetime: static data
// an op makes from nothing counted (a constant, poison, a small big) and
// what is read from it, which idr-rc grades once, at its start; consuming
// one takes a reference of its own (idr.dup), at the heap, which no count
// reaches either. A value is frame when it may reach a cell of its frame
// (idr.cell.stack): a field read from it, a constructor or closure that
// holds it, and whatever it is forwarded into. Heap is every value's until
// idr-rc decides otherwise, the case 0 a grade written without a lifetime
// has.
def Idr_Lifetime : I32EnumAttr<"Lifetime", "how long what a value reaches lives", [
    I32EnumAttrCase<"Heap", 0, "heap">, I32EnumAttrCase<"Frame", 1, "frame">,
    I32EnumAttrCase<"Static", 2, "static">]> {
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

// The three kinds of program a refusal names: a megamorphic construct,
// whose choices at a site (the types, instances, implementations or shapes
// it can meet) no compile-time analysis bounds; one outside the language
// this compiler compiles, as %foreign, threads, finalizers and raw pointers
// are, or one a total analysis proves the program cannot meet (a reference
// knot counting would never free, an in-place promise shared); and a
// program Idris itself rejects, which does not elaborate. No limit of the
// compiler's is a kind: a limit is lifted by a representation, never
// refused.
def Idr_Megamorphic : I32EnumAttrCase<"Megamorphic", 0, "megamorphic">;
def Idr_OutsideLanguage : I32EnumAttrCase<"OutsideLanguage", 1, "outside the language">;
def Idr_UserError : I32EnumAttrCase<"UserError", 2, "user error">;
def Idr_RuleCategory : I32EnumAttr<"RuleCategory", "the kind of program a refusal names", [
    Idr_Megamorphic, Idr_OutsideLanguage, Idr_UserError]> {
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
// as: `unsupported (<phrase>): ...` for a megamorphic construct or one
// outside the language, while the refusal of a program Idris rejects
// carries Idris's own message. The frontend's and the pipeline's are
// one list: C++ reads it from here, and idris-mlir-tblgen writes the Idris
// side's `Rule` from it. A phrase of two words is no keyword, so the
// attribute writes it as a string. A value, once given, is never given to
// another rule.
def Idr_Rule : I32EnumAttr<"Rule", "the rule a refusal of a program names", [
    Idr_RuleCase<"ProgramShape", 0, "program", Idr_OutsideLanguage>,
    Idr_RuleCase<"TrustedLibrary", 1, "library", Idr_OutsideLanguage>,
    Idr_RuleCase<"WorldUse", 2, "world", Idr_OutsideLanguage>,
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
    Idr_RuleCase<"Runtime", 30, "runtime", Idr_OutsideLanguage>,
    // A program Idris does not elaborate: the refusal carries Idris's own
    // message.
    Idr_RuleCase<"Elaboration", 31, "elaboration", Idr_UserError>]> {
  let cppNamespace = "::idr";
  let genSpecializedAttr = 0;
  let parameterPrinter = "$_printer.printKeywordOrString(::idr::stringifyRule($_self))";
}

//===----------------------------------------------------------------------===//
// Guards
//===----------------------------------------------------------------------===//

// The condition a guard checks (idr.check.*), spelled as its op is named.
// Each case is a def, which a guard op (Idr_CheckOp) and a partial op's
// mark (Idr_Guarded) take as the record itself, so a kind no case names is
// TableGen's error, never a search by name. No case is named as anything
// in Idris's prelude is: idris-mlir-tblgen writes the cases into Idris as
// they are.
def Idr_Nonzero : I32EnumAttrCase<"Nonzero", 0, "nonzero">;
def Idr_InBounds : I32EnumAttrCase<"InBounds", 1, "in_bounds">;
def Idr_Nonempty : I32EnumAttrCase<"Nonempty", 2, "nonempty">;
def Idr_Finite : I32EnumAttrCase<"Finite", 4, "finite">;
def Idr_InRange : I32EnumAttrCase<"InRange", 5, "range">;
def Idr_CheckKind : I32EnumAttr<"CheckKind", "the condition a guard checks", [
    Idr_Nonzero, Idr_InBounds, Idr_Nonempty, Idr_Finite, Idr_InRange]> {
  let cppNamespace = "::idr";
  let genSpecializedAttr = 0;
}

//===----------------------------------------------------------------------===//
// What an op or a type says once
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

// A grade op whose result is its operand's value, its identity and its
// exclusivity kept. idr.share carries its operand but forgets
// exclusivity, so it lacks this.
def Idr_SameValue : NativeOpTrait<"SameValue"> { let cppNamespace = "::idr"; }

// An op whose result takes a reference of its own to what it reads, which
// its lowering counts: idr.dup of a view, idr.array.get of an element. Any
// other op that reads a value, or a part of one, gives a view of it: the
// owned walk gives a result a reference only from a source its op
// declares (OwnedWalk::make).
def Idr_TakesReference : NativeOpTrait<"TakesReference"> { let cppNamespace = "::idr"; }

// A partial op's guard: the guard op that checks `checkKind` (a case of
// Idr_CheckKind) is given the op's values `guardedOperands`, named in the
// guard op's operand order, the operand it guards first, and the program
// crashes with the message `crashCause` unless the condition holds. An op
// guarded on several operands carries one of these per guard.
// idris-mlir-tblgen generates from these the guards the frontend builds
// before each op, and, for an op with Idr_GuardedOp, the C++
// specialization ::idr::Guarded<Op> its folder and its speculation read
// (Traits.h), so the C++ names no guard by hand.
class Idr_Guarded<list<string> guardedOperands, I32EnumAttrCase checkKind, string crashCause>
    : GenInternalOpTrait<"Guarded"> {
  list<string> operands = guardedOperands;
  I32EnumAttrCase kind = checkKind;
  string cause = crashCause;
}

// How a guard over a value of a type the runtime's C ABI holds as one value
// has a count of bytes from it: none, the bytes of a string, or the length
// of an array.
class Idr_AbiCount;
def Idr_NoCount : Idr_AbiCount;
def Idr_BytesOf : Idr_AbiCount;
def Idr_LengthOf : Idr_AbiCount;

// A type constraint the runtime's C ABI holds as one value, mixed into the
// constraint where it is defined: `word`, the C ABI's word the value is (a
// case of idris-mlir-tblgen's words: World, Str, Big, Buffer, ...), and
// `count`, how a guard over such a value has a count of bytes from it.
// idris-mlir-tblgen reads both fields, for the runtime's prototypes and for
// the Idris side's guards, so no table of constraint names says them again.
class Idr_AbiWord<string word, Idr_AbiCount count> {
  string abiWord = word;
  Idr_AbiCount abiCount = count;
}

//===----------------------------------------------------------------------===//
// Constraints the op families share
//===----------------------------------------------------------------------===//

// Base's list, which the string ops walk and build: a data type of kind
// `list`, a nil and a cons of an element and the list, whose element is one
// of `elements`. The frontend holds it in place, as every type, and
// layout::fit boxes it with the other cycles, after which the program's
// verifier holds no type that contains itself in place.
class Idr_BaseListOf<list<Type> elements> : Type<And<[
    CPred<"::idr::dataTypeOf($_self) && ::idr::dataTypeOf($_self).getKind() == ::idr::SumKind::BaseList">,
    Or<!foreach(e, elements, SubstLeaves<"$_self", "::idr::dataTypeOf($_self).getListElement()", e.predicate>)>]>,
    "base's list of " # !interleave(!foreach(e, elements, e.summary), " or "), "::mlir::Type">;

// What a closure, a suspension or a delay captures: a capture becomes a
// field of a constructor of its sum, so any value a field holds
// (isFieldType) but the world, which none of them holds.
def Idr_Capture : Type<CPred<"::idr::isFieldType($_self) && !::idr::isWorld($_self)">,
                       "a value a field holds, other than the world", "::mlir::Type">;

// The constructor tags a match's cases name: never negative.
def Idr_TagArray : ConfinedAttr<DenseI32ArrayAttr, [DenseArrayNonNegative<DenseI32ArrayAttr>]>;

// The fields of a cell left as holes for destinations to write
// (idr.cell.init's `holes`): positions, never negative, each after the one
// before, so a field is a hole at most once.
def Idr_HolePositions : ConfinedAttr<DenseI32ArrayAttr,
    [DenseArrayNonNegative<DenseI32ArrayAttr>, DenseArrayStrictlySorted<DenseI32ArrayAttr>]>;

#endif // IDR_BASE
