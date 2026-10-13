// What an op of the idr dialect declares once, for every pass to derive
// from: the resources of its effects, its base class, and its traits and
// interfaces, whose C++ halves are in IdrDialect.h.

#ifndef IDR_INTERFACES
#define IDR_INTERFACES

include "idr/IR/IdrTypes.td"

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

// The op lowers to a call of the runtime's C function named after it:
// `idr.str.append` calls `idris_rt_str_append`. Lowering gives every op
// with this trait that pattern.
def Idr_CallsRuntime : NativeOpTrait<"CallsRuntime"> {
  let cppNamespace = "::idr";
}

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

// Where an op takes over the reference an operand holds, said once, here,
// beside the op: idr-rc places counts by it (idr::consumes), and after idr-rc
// an op whose only effect is what it takes over reports a Free of what it
// takes owned (idr::consumedEffects), so that no pass drops it as dead.
def Idr_ConsumingOpInterface : OpInterface<"ConsumingOpInterface"> {
  let cppNamespace = "::idr";
  let description = "An op that takes over the reference an operand holds.";
  let methods = [
    InterfaceMethod<"Whether the operand at `number` is taken over.",
                    "bool", "consumesOperand", (ins "unsigned":$number), "",
                    [{ return $_op.consumedByTrait(number); }]>,
  ];
}

// `groups`: the ODS operand groups the op takes over, as "0" or "0, 2".
// The trait is ::idr::ConsumesOperands<groups>::Impl: a ParamNativeOpTrait
// names ::mlir::OpTrait:: unless its class sets the namespace, as
// Idr_MayCrashTrait does.
class Idr_ConsumesOperandsTrait<string groups>
    : ParamNativeOpTrait<"ConsumesOperands", groups> {
  let cppNamespace = "::idr";
}
class Idr_Consumes<string groups>
    : TraitList<[Idr_ConsumesOperandsTrait<groups>, Idr_ConsumingOpInterface]>;

// An op whose only effect is what it takes over, reported by the trait.
class Idr_ConsumesOnly<string groups>
    : TraitList<[Idr_Consumes<groups>, MemoryEffectsOpInterface, AlwaysSpeculatable]>;

// An op Idris names as a primitive: idris-mlir-tblgen generates its
// constructor of `IdrPrim` (or `IdrRegionPrim`) for the Idris side.
def Idr_Primitive : NativeOpTrait<"Primitive"> { let cppNamespace = "::idr"; }

// The result is the operand's value, at whatever grade the result has.
def Idr_ResultCarriesOperand : NativeOpTrait<"ResultCarriesOperand"> {
  let cppNamespace = "::idr";
}

#endif // IDR_INTERFACES
