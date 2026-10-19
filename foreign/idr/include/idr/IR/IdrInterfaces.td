// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What an op or a type of the idr dialect declares once, for every pass to
// derive from: the resources of an op's effects, its base class, and its
// traits and interfaces, whose C++ halves are in IdrDialect.h and
// Traits.h; what a value of a type holds, which every type answers; and
// what a literal of a type is.

#ifndef IDR_INTERFACES
#define IDR_INTERFACES

include "idr/IR/IdrBase.td"
include "idr/IR/IdrFlow.td"

//===----------------------------------------------------------------------===//
// What a value holds
//===----------------------------------------------------------------------===//

// What a value of a type holds, asked of the type and answered by it: every
// type of the dialect declares it, a data type from its body, once, and the
// builtin types a value may have answer it as external models
// (lib/IR/Types.cpp). So no pass lists types to learn one of these, and two
// passes cannot answer differently. A grade answers as the value it grades.
def Idr_ValueFactsTypeInterface : TypeInterface<"ValueFactsTypeInterface"> {
  let cppNamespace = "::idr";
  let description = [{
    What a value of the type holds: a reference a count accounts for, the
    world; whether the type alone makes every value of it used exactly
    once; whether the owned stage counts the value; and whether the value is
    one pointer to a cell.
  }];
  let methods = [
    InterfaceMethod<[{
        Whether a value of the type holds a reference a count accounts for,
        itself (a cell's address, a big's word, an array's cell) or in what
        it holds in place (a slot of a sum held in place).
      }], "bool", "holdsReferences">,
    InterfaceMethod<[{
        Whether a value of the type may hold the world: it is the world, or
        holds a value that may, in place, in a box or in an array's
        elements. A closure or a suspension never captures one.
      }], "bool", "holdsWorld">,
    InterfaceMethod<[{
        Whether every value of the type is used exactly once by the type
        alone, as the world, a destination and a cell are: no grade states
        it, and a grade of such a type is refused.
      }], "bool", "isLinearByType">,
    InterfaceMethod<[{
        Whether the owned stage counts a value of the type: it holds a
        reference and lives where counts reach it. A value array holds its
        buffer's reference but is counted as that buffer, after
        bufferization.
      }], "bool", "isCounted">,
    InterfaceMethod<[{
        Whether every value of the type is one pointer, never null, to a
        cell that is live or static, which starts with its header: a box, a
        string, a closure or a suspension. A counted value is not enough: a
        big's word is a pointer only when it is not small, a reuse token is
        null where its cell was shared, a sum held in place leaves the slots
        of the other constructors empty, and an array is a descriptor of
        several words.
      }], "bool", "isCellPointer">,
  ];
}

//===----------------------------------------------------------------------===//
// What a literal of a type is
//===----------------------------------------------------------------------===//

// What a literal of a type is, asked of the type: which attributes are its
// literals, and how one is read. The types a literal match takes and a
// constant builds answer it, the builtin integers as external models, so
// neither the match nor the constant lists the types that have literals.
def Idr_LiteralTypeInterface : TypeInterface<"LiteralTypeInterface"> {
  let cppNamespace = "::idr";
  let methods = [
    InterfaceMethod<"Whether the attribute is a literal of this type.", "bool", "isLiteral",
                    (ins "::mlir::Attribute":$literal)>,
    InterfaceMethod<"Reads a literal of this type.", "::mlir::ParseResult", "parseLiteral",
                    (ins "::mlir::AsmParser &":$parser, "::mlir::Attribute &":$literal)>];
}

//===----------------------------------------------------------------------===//
// What an op declares once, for every pass to derive from
//===----------------------------------------------------------------------===//

def Idr_CrashResource : Resource<"::idr::CrashResource">;
def Idr_IOResource : Resource<"::idr::IOResource">;
def Idr_DivergenceResource : Resource<"::idr::DivergenceResource">;
def Idr_LinResource : Resource<"::idr::LinResource">;
def Idr_ReferenceResource : Resource<"::idr::ReferenceResource">;
def Idr_MemoStateResource : Resource<"::idr::MemoStateResource">;

// An op's verify() runs before the ops of its regions are verified, when one
// of them may still hold a null operand or lack an attribute: a tool that
// drops uses, as idris-mlir-reduce does, leaves such ops behind. So a check
// that reads an op of a region is in verifyRegions (hasRegionVerifier),
// which runs after them, and verify() reads only the op and the arguments
// of its regions' blocks.
class Idr_Op<string mnemonic, list<Trait> traits = []>
    : Op<Idr_Dialect, mnemonic, traits>;

// An op that may end the program, and what its crash reports, the text of
// the crash message. An op that cannot crash does not hold it.
def Idr_MayCrashOpInterface : OpInterface<"MayCrashOpInterface"> {
  let cppNamespace = "::idr";
  let description = "An op that may end the program with a crash.";
  let methods = [
    InterfaceMethod<"What the crash reports.", "::llvm::StringRef", "getCrashCause">,
  ];
}

// An op that may crash: it writes the crash resource and the IO resource,
// so no pass drops it or moves it across output, and it is not
// speculatable, which an op without ConditionallySpeculatable is to MLIR.
def Idr_MayCrash : TraitList<[DeclareOpInterfaceMethods<Idr_MayCrashOpInterface>,
    MemoryEffects<[MemWrite<Idr_CrashResource>, MemWrite<Idr_IOResource>]>]>;

// What a pass asks of any guard, so that none lists the guards: the
// condition it checks, and the operand it guards.
def Idr_GuardOpInterface : OpInterface<"GuardOpInterface"> {
  let cppNamespace = "::idr";
  let description = "A guard: crashes unless its condition holds, else gives its operand.";
  let methods = [
    InterfaceMethod<"The condition the guard checks.", "::idr::CheckKind", "getKind">,
    InterfaceMethod<"The operand whose value the guard's result passes on.",
                    "::mlir::Value", "getGuarded">,
  ];
}

// A pure total op whose guards (Idr_Guarded) read only its own operands, one
// value each: the trait ::idr::GuardedOp supplies `guardHolds(adaptor)`,
// which its folder asks before computing on constants, and
// `getSpeculatability()`, which an op that lists ConditionallySpeculatable
// beside it takes as its own, as AlwaysSpeculatableImplTrait supplies an
// always speculatable op's. Both read the guards from the specialization
// ::idr::Guarded<Op> idris-mlir-tblgen generates from the op's marks, at
// compile time. The IO buffer ops and the array accesses, whose guards read
// a count of bytes or a group of indices, do not carry it: they neither fold
// nor speculate.
def Idr_GuardedOp : NativeOpTrait<"GuardedOp"> { let cppNamespace = "::idr"; }

// What a pass asks of a match, so that none lists the match ops: the value
// it takes apart, the region of each case and the default, and how to
// remake it with fewer cases. Which region a constant scrutinee takes is
// RegionBranchOpInterface's getEntrySuccessorRegions, not a method of this.
def Idr_MatchOpInterface : OpInterface<"MatchOpInterface"> {
  let cppNamespace = "::idr";
  let description = "A match: a region per case of its scrutinee, and a default.";
  let methods = [
    InterfaceMethod<"The value the match takes apart.", "::mlir::Value", "getScrutinee">,
    InterfaceMethod<"The number of its cases.", "unsigned", "getNumCases">,
    InterfaceMethod<"The region of case `index`.", "::mlir::Region &", "getCaseRegion",
                    (ins "unsigned":$index)>,
    InterfaceMethod<[{The default region: empty when an idr.match's cases are
                      exhaustive, else one block binding the scrutinee.}],
                    "::mlir::Region &", "getDefaultRegion">,
    InterfaceMethod<[{The index of `region`, one of its case regions. The default
                      is no case: a caller tests for it first.}],
                    "unsigned", "caseOf", (ins "::mlir::Region &":$region)>,
    InterfaceMethod<[{The constructor the case region `region` is entered at; none
                      for the default and for every region of idr.match_lit.}],
                    "std::optional<::idr::Tag>", "knownTag", (ins "::mlir::Region &":$region)>,
    InterfaceMethod<[{The same match with `results`, the cases `keptCases` in
                      their order and `defaultRegion` as its default, built with
                      `rewriter` in its place.}],
                    "::mlir::Operation *", "rebuild",
                    (ins "::mlir::RewriterBase &":$rewriter, "::mlir::TypeRange":$results,
                         "::llvm::ArrayRef<unsigned>":$keptCases,
                         "::mlir::Region *":$defaultRegion)>,
  ];
}

// What a pass asks of an op that runs the function a label names, so that
// none lists them: the value whose label decides what runs.
def Idr_RunsLabelsOpInterface : OpInterface<"RunsLabelsOpInterface"> {
  let cppNamespace = "::idr";
  let description = "An op that runs the function a closure's or a suspension's label names.";
  let methods = [
    InterfaceMethod<"The closure applied or the suspension forced.", "::mlir::Value",
                    "getLabelCarrier">,
  ];
}

// What an idr.array.yield asks of the op it ends a region of, so that it
// lists none: the memory its leading values move into, one each, arrays or
// a memo cell. The yield forwards the values after them.
def Idr_YieldTargetsOpInterface : OpInterface<"YieldTargetsOpInterface"> {
  let cppNamespace = "::idr";
  let description = "An op whose region yields values into memory it holds.";
  let methods = [
    InterfaceMethod<"The arrays or memo cell the yield's leading values move into, one each.",
                    "::mlir::ValueRange", "getYieldTargets">,
  ];
}

// What a pass asks of any op of the array language's generating set, so
// that none lists them: a region that binds the indices of an iteration
// domain first and runs once per index, how each dimension of the domain is
// visited and how large it is, and the arrays held at the indices of its
// parallel dimensions. The size is given twice, as code and as a term of
// value bounds, because a term makes nothing and code needs a value: both
// are read from the one place the op holds the size.
def Idr_GeneratingOpInterface : OpInterface<"GeneratingOpInterface",
                                             [Idr_YieldTargetsOpInterface]> {
  let cppNamespace = "::idr";
  let description = "An op of the generating set: a region run once per index of a domain.";
  let methods = [
    InterfaceMethod<"The number of dimensions of the domain.", "unsigned", "getRank">,
    InterfaceMethod<"How each dimension of the domain is visited, outermost first.",
                    "::llvm::SmallVector<::idr::Iteration>", "getIterations">,
    InterfaceMethod<"The indices the region binds, one per dimension of the domain.",
                    "::mlir::Block::BlockArgListType", "getIndices">,
    InterfaceMethod<[{The size of dimension `dim` of the domain, made with `b`
                      where it is read from an operand's shape.}],
                    "::mlir::OpFoldResult", "getExtent",
                    (ins "::mlir::OpBuilder &":$b, "unsigned":$dim)>,
    InterfaceMethod<"The same size as value bounds names it, making nothing.",
                    "::mlir::ValueBoundsConstraintSet::Variable", "getExtentBound",
                    (ins "unsigned":$dim)>,
    InterfaceMethod<[{The arrays it makes or folds, each held at the indices of
                      the domain's parallel dimensions.}],
                    "::mlir::ValueRange", "getHeldArrays">,
  ];
}

// What a pass asks of an element rebuilt in its place, so that none lists
// the ops that rebuild one: the array a world orders or the value array's
// buffer that holds it, its indices, one i64 per dimension, the element the
// region binds, which moves out with the reference its place held, and the
// values the region gives after the element, which leave the op. The
// region's first value moves back in over the place the element left.
def Idr_UpdateOpInterface : OpInterface<"UpdateOpInterface", [Idr_YieldTargetsOpInterface]> {
  let cppNamespace = "::idr";
  let description = "An element of an array or of a value array's buffer rebuilt in its place.";
  let methods = [
    // Read off the operand, never the op's typed accessor: idr-rc grades a
    // buffer before it gives each read of it the plain view the op takes,
    // and asks what each update consumes in between.
    InterfaceMethod<"The array or buffer that holds the element.", "::mlir::Value", "getArray",
                    (ins), [{ return $_op.getArrayMutable().get(); }]>,
    InterfaceMethod<"Its memref type, with no grade.", "::mlir::MemRefType", "getArrayType">,
    InterfaceMethod<"The element's indices, one per dimension.", "::mlir::OperandRange",
                    "getIndices">,
    InterfaceMethod<"The element moved out, which the region rebuilds.", "::mlir::BlockArgument",
                    "getElement">,
    InterfaceMethod<"The values the region gives after the element.", "::mlir::ResultRange",
                    "getOuts">,
  ];
}

// What a pass asks of a fold along an array's last axis, so that none tells
// a fold from a scan to read one: the accumulators' first values, the
// length of the axis, how many leading axes each step's frame has, and the
// accumulators the region binds.
def Idr_LastAxisFoldOpInterface : OpInterface<"LastAxisFoldOpInterface"> {
  let cppNamespace = "::idr";
  let description = "A fold or a scan of accumulators along an array's last axis.";
  let methods = [
    InterfaceMethod<"The accumulators' first values.", "::mlir::OperandRange", "getInits">,
    InterfaceMethod<"The length of the axis folded.", "::mlir::Value", "getLength">,
    InterfaceMethod<"The rank of the frame each step reads.", "unsigned", "getFrameRank">,
    InterfaceMethod<"The accumulators the region binds.", "::mlir::Block::BlockArgListType",
                    "getAccumulators">,
  ];
}

// What a pass asks of an op that builds a string, so that none lists the
// builders: whether the string is never empty, whether output of it may
// write the pieces it is built of instead, and whether its first character
// is known without building it. Each builder beside a predicate is called
// only when the predicate holds, so a pass weighing a rewrite asks without
// building.
def Idr_StrBuilderOpInterface : OpInterface<"StrBuilderOpInterface"> {
  let cppNamespace = "::idr";
  let description = "An op that builds a string from pieces.";
  let methods = [
    InterfaceMethod<"Whether the string it builds is never empty.", "bool", "nonEmpty">,
    InterfaceMethod<"Whether output of the string may write its pieces instead.", "bool",
                    "writesInPieces">,
    InterfaceMethod<[{Writes its pieces with `b` after `world`, and gives the world
                      after; only where writesInPieces holds.}],
                    "::mlir::Value", "writePieces",
                    (ins "::mlir::OpBuilder &":$b, "::mlir::Value":$world)>,
    InterfaceMethod<"Whether its first character is known without building the string.", "bool",
                    "knowsFirstChar">,
    InterfaceMethod<"Builds its first character with `b`; only where knowsFirstChar holds.",
                    "::mlir::Value", "firstChar", (ins "::mlir::OpBuilder &":$b)>,
  ];
}

// The idr.io ops, which the frontend orders in the world's chain
// (primPerformsIO). What a function may do is idr::bodyEffect's, which
// reads IO off the worlds a function takes or forges, not off this.
def Idr_PerformsIO : NativeOpTrait<"PerformsIO"> {
  let cppNamespace = "::idr";
}

// An IO op whose effect the program's outside can observe: output, input,
// a file, a clock. An array or a buffer is memory only the program reads
// back through its own ops, a forged world only orders a chain, and an
// error's text is the C library's, the same at every call: none of those
// carries this trait. It is said here, on the op's class, once: a memo
// label that reaches one is `by_name`, so its effect happens where its
// value is demanded (idr-defunctionalize).
def Idr_ObservableIO : NativeOpTrait<"ObservableIO"> {
  let cppNamespace = "::idr";
}

// An op whose only effect is what it takes over: after idr-rc it reports a
// Free of what it takes owned (idr::consumedEffects), so that no pass drops
// it as dead. What it takes over is its flow's (IdrFlow.td), which
// idr::consumes reads. The effects are ::idr::ConsumesOperands's.
def Idr_ConsumesOperands : NativeOpTrait<"ConsumesOperands"> { let cppNamespace = "::idr"; }
def Idr_ConsumesOnly : TraitList<[Idr_ConsumesOperands, MemoryEffectsOpInterface,
                                  AlwaysSpeculatable]>;

// An op Idris names as a primitive: idris-mlir-tblgen generates its
// constructor of `IdrPrim` (or `IdrRegionPrim`) for the Idris side.
def Idr_Primitive : NativeOpTrait<"Primitive"> { let cppNamespace = "::idr"; }

// An op whose result is its operand at run time: a change of grade, of
// linearity or of kind, which idr-lower lowers to its operand's components
// (::idr::NoRuntimeForm).
def Idr_NoRuntimeForm : NativeOpTrait<"NoRuntimeForm"> { let cppNamespace = "::idr"; }

// The result is the operand's value, at whatever grade the result has
// (::idr::ResultCarriesOperand, which verifies it), which a pass looks
// through. Held through Idr_ResultCarriesOperand.
def Idr_CarriesOperand : NativeOpTrait<"ResultCarriesOperand"> { let cppNamespace = "::idr"; }

// An op that carries its operand is its operand at run time, so carrying
// says Idr_NoRuntimeForm with it, once; and no analysis of integer ranges
// loses the value through it: its result has its operand's range
// (::idr::ranges::carried), as every range analysis reads it, upstream's
// included.
def Idr_ResultCarriesOperand : TraitList<[Idr_CarriesOperand, Idr_NoRuntimeForm,
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRangesFromOptional"]>]>;

#endif // IDR_INTERFACES
