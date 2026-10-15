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
    world, a closure; and whether the owned stage counts the value.
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
