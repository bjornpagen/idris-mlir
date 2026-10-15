// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What an op or a type of the idr dialect declares once, for every pass to
// derive from: the resources of an op's effects, its base class, and its
// traits and interfaces, whose C++ halves are in IdrDialect.h; and what a
// value of a type holds, which every type answers.

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
    world, a closure; whether the owned stage counts the value; and whether
    the value is one pointer to a cell.
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
        Whether a value of the type may hold a closure: it is one, or a
        constructor of a sum of closures, or holds a value that may, in
        place, in a box or in an array's elements.
      }], "bool", "holdsClosure">,
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
// What an op declares once, for every pass to derive from
//===----------------------------------------------------------------------===//

def Idr_CrashResource : Resource<"::idr::CrashResource">;
def Idr_IOResource : Resource<"::idr::IOResource">;
def Idr_DivergenceResource : Resource<"::idr::DivergenceResource">;
def Idr_LinResource : Resource<"::idr::LinResource">;
def Idr_ReferenceResource : Resource<"::idr::ReferenceResource">;

// An op's verify() runs before the ops of its regions are verified, when one
// of them may still hold a null operand or lack an attribute: a tool that
// drops uses, as idris-mlir-reduce does, leaves such ops behind. So a check
// that reads an op of a region is in verifyRegions (hasRegionVerifier),
// which runs after them, and verify() reads only the op and the arguments
// of its regions' blocks.
class Idr_Op<string mnemonic, list<Trait> traits = []>
    : Op<Idr_Dialect, mnemonic, traits>;

// An op that may end the program. Its cause is the text of the crash
// message; its effects and speculatability follow.
def Idr_MayCrashOpInterface : OpInterface<"MayCrashOpInterface"> {
  let cppNamespace = "::idr";
  let description = "An op that may end the program with a crash.";
  let methods = [
    InterfaceMethod<"What the crash reports, or nothing when the op cannot crash.",
                    "std::optional<::llvm::StringRef>", "getCrashCause">,
  ];
}

// `allocates`: the op also allocates its result (MemAlloc).
class Idr_MayCrashTrait<bit allocates>
    : ParamNativeOpTrait<"MayCrash", !if(allocates, "true", "false")> {
  let cppNamespace = "::idr";
}

class Idr_MayCrash<bit allocates = 0> : TraitList<[Idr_MayCrashTrait<allocates>,
    DeclareOpInterfaceMethods<Idr_MayCrashOpInterface>,
    MemoryEffectsOpInterface, ConditionallySpeculatable]>;

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

// What a pass asks of any op of the array language's generating set, so
// that none lists them: a region that binds the indices of an iteration
// domain first and runs once per index, how each dimension of the domain is
// visited and how large it is, and the arrays held at the indices of its
// parallel dimensions. The size is given twice, as code and as a term of
// value bounds, because a term makes nothing and code needs a value: both
// are read from the one place the op holds the size.
def Idr_GeneratingOpInterface : OpInterface<"GeneratingOpInterface"> {
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
def Idr_UpdateOpInterface : OpInterface<"UpdateOpInterface"> {
  let cppNamespace = "::idr";
  let description = "An element of an array or of a value array's buffer rebuilt in its place.";
  let methods = [
    InterfaceMethod<"The array or buffer that holds the element.", "::mlir::Value", "getArray">,
    InterfaceMethod<"Its memref type, with no grade.", "::mlir::MemRefType", "getArrayType">,
    InterfaceMethod<"The element's indices, one per dimension.", "::mlir::OperandRange",
                    "getIndices">,
    InterfaceMethod<"The element moved out, which the region rebuilds.", "::mlir::BlockArgument",
                    "getElement">,
    InterfaceMethod<"The values the region gives after the element.", "::mlir::ResultRange",
                    "getOuts">,
  ];
}

// The idr.io ops, which idr-effects looks for.
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
// idr::consumes reads; `groups`, the ODS operand groups written with it, say
// nothing more. The trait is ::idr::ConsumesOperands<groups>::Impl: a
// ParamNativeOpTrait names ::mlir::OpTrait:: unless its class sets the
// namespace, as Idr_MayCrashTrait does.
class Idr_ConsumesOperandsTrait<string groups>
    : ParamNativeOpTrait<"ConsumesOperands", groups> {
  let cppNamespace = "::idr";
}
class Idr_ConsumesOnly<string groups>
    : TraitList<[Idr_ConsumesOperandsTrait<groups>, MemoryEffectsOpInterface,
                 AlwaysSpeculatable]>;

// An op Idris names as a primitive: idris-mlir-tblgen generates its
// constructor of `IdrPrim` (or `IdrRegionPrim`) for the Idris side.
def Idr_Primitive : NativeOpTrait<"Primitive"> { let cppNamespace = "::idr"; }

// The result is the operand's value, at whatever grade the result has.
def Idr_ResultCarriesOperand : NativeOpTrait<"ResultCarriesOperand"> {
  let cppNamespace = "::idr";
}

#endif // IDR_INTERFACES
