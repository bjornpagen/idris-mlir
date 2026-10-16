// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What may crash or not return in the idr dialect: a crash, a loop that
// may not end, and the guards whose conditions the total ops need.

#ifndef IDR_CHECK_OPS
#define IDR_CHECK_OPS

include "idr/IR/IdrAttrs.td"
include "idr/IR/IdrInterfaces.td"
include "idr/IR/IdrBigOps.td"

//===----------------------------------------------------------------------===//
// Crashes and loops
//===----------------------------------------------------------------------===//

// An op that does not return: the runtime function it lowers to is
// noreturn, and what follows it is unreachable.
def Idr_NoReturn : NativeOpTrait<"NoReturn"> { let cppNamespace = "::idr"; }

// A case the definition does not cover, followed by ub.unreachable.
def Idr_CrashOp : Idr_Op<"crash", [Idr_MayCrash<>, Idr_NoReturn]> {
  let summary = "ends the program with a message naming the cause";
  let arguments = (ins StrAttr:$message);
  let assemblyFormat = "$message attr-dict";
}

// A trusted library's crash of a string it computed. The message is the
// string's text. The op does not return; Emit follows it with unreachable.
def Idr_CrashStrOp : Idr_Op<"crash_str", [Idr_Runtime<"idris_rt_crash_str">, Idr_MayCrash<>,
    Idr_NoReturn, Idr_Primitive]> {
  let summary = "ends the program with a string's text";
  let arguments = (ins Idr_StrRead:$message);
  let assemblyFormat = "custom<StrRead>($message, type($message)) attr-dict";
  let extraClassDefinition = [{
    std::optional<::llvm::StringRef> $cppClass::getCrashCause() {
      return ::llvm::StringRef("idris_crash");
    }
  }];
}

// Created by idr-tail-loops in loops of functions that are not total; never
// written by Emit. MLIR deletes a region op without effects even if it never
// finishes; this op's effect keeps such a loop, and orders it with output as
// a crash is. It lowers to llvm.sideeffect.
def Idr_MayLoopOp : Idr_Op<"may_loop", [MemoryEffects<[
    MemWrite<Idr_DivergenceResource>, MemWrite<Idr_IOResource>]>]> {
  let summary = "marks one iteration of a loop that may not terminate";
  let assemblyFormat = "attr-dict";
}

//===----------------------------------------------------------------------===//
// Guards
//===----------------------------------------------------------------------===//

// A partial primitive is a guard and a total op. The guard crashes with its
// cause, the text of the crash message, when its condition fails, and
// otherwise gives its operand, which the total op takes in the operand's
// place: the op stays below its check by data dependence, and a pass that
// builds the op on an operand nothing proved builds the guard too. A proof
// is the absence of the guard. The total op names its guard in its ODS
// (Idr_Guarded), which the Idris side's guards are generated from. A guard
// folds to its operand where the operand shows its condition holds, which
// the guard op itself decides (holds, lib/IR/OpsChecks.cpp): a total op's
// folder asks the same guard op whether its constants may be computed on.
// The result of a guard with an integer range is the operand's range
// clamped by the condition. The guard's kind is the case of CheckKind
// `kind` names, found in the enum, so a kind no case names fails here. The
// operand a guard guards is its first, which its folder and its lowering
// give as its result; any other is what the condition reads beside it.
class Idr_CheckOp<string mnemonic, string kind, list<Trait> traits = []>
    : Idr_Op<"check." # mnemonic, !listconcat(traits, [Idr_MayCrash<>,
        DeclareOpInterfaceMethods<Idr_GuardOpInterface>])> {
  defvar kindCases = !filter(c, Idr_CheckKind.enumerants, !eq(c.symbol, kind));
  assert !not(!empty(kindCases)), "'" # kind # "' is no case of CheckKind";
  EnumCase checkKind = !if(!empty(kindCases), ?, !head(kindCases));
  // nonzero and nonempty also take their operand's reference over and give
  // it to their result, an edge of their flow; a guard's effects are its
  // crash's alone.
  let extraClassDeclaration = [{
    // Whether the condition holds of `constants`, the guard's operands in
    // order: what its folder and every folder of the total ops it guards
    // ask before computing. A null one is not a constant, and the
    // condition does not hold of it.
    static bool holds(::llvm::ArrayRef<::mlir::Attribute> constants);
  }];
  let extraClassDefinition = [{
    std::optional<::llvm::StringRef> $cppClass::getCrashCause() { return getCause(); }
    ::idr::CheckKind $cppClass::getKind() { return ::idr::CheckKind::}] # checkKind.symbol # [{; }
    ::mlir::Value $cppClass::getGuarded() { return getOperation()->getOperand(0); }
  }];
  let hasFolder = 1;
}

def Idr_CheckNonzeroOp : Idr_CheckOp<"nonzero", "Nonzero", [SameOperandsAndResultType,
    DeclareOpInterfaceMethods<Idr_FlowOpInterface>,
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  let summary = "the value, which must not be zero, else the program crashes";
  let arguments = (ins AnyTypeOf<[Idr_Int, Idr_BigValue]>:$value, StrAttr:$cause);
  let results = (outs AnyTypeOf<[Idr_Int, Idr_BigValue]>:$checked);
  let assemblyFormat = "$value `,` $cause attr-dict `:` type($value)";
}

// An index of a string or of an array of one dimension, below its length.
// The guard takes what is indexed, not a length computed apart from it, so
// that the index is checked against the very value the op reads.
def Idr_CheckInBoundsOp : Idr_CheckOp<"in_bounds", "InBounds", [
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRangesFromOptional"]>]> {
  let summary = "the index, which must be at least 0 and below the length of what it indexes, else the program crashes";
  let arguments = (ins I64:$index, AnyTypeOf<[Idr_StrRead, Idr_Rank1ArrayValue]>:$indexed,
                       StrAttr:$cause);
  let results = (outs I64:$checked);
  let assemblyFormat = "$index `,` $indexed `,` $cause attr-dict `:` type($indexed)";
}

def Idr_CheckNonemptyOp : Idr_CheckOp<"nonempty", "Nonempty", [SameOperandsAndResultType,
    DeclareOpInterfaceMethods<Idr_FlowOpInterface>]> {
  let summary = "the string, which must have at least one byte, else the program crashes";
  let arguments = (ins Idr_StrValue:$str, StrAttr:$cause);
  let results = (outs Idr_StrValue:$checked);
  let assemblyFormat = "$str `,` $cause attr-dict `:` type($str)";
}

def Idr_CheckFiniteOp : Idr_CheckOp<"finite", "Finite"> {
  let summary = "the value, which must be neither NaN nor infinite, else the program crashes";
  let arguments = (ins F64:$value, StrAttr:$cause);
  let results = (outs F64:$checked);
  let assemblyFormat = "$value `,` $cause attr-dict";
}

// The bytes [offset, offset + count) of something of `size` bytes: both at
// least 0, and the end, computed without overflow, at most the size.
def Idr_CheckRangeOp : Idr_CheckOp<"range", "InRange", [
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  let summary = "the offset, whose range of `count` bytes must lie in `size`, else the program crashes";
  let arguments = (ins I64:$offset, I64:$count, I64:$size, StrAttr:$cause);
  let results = (outs I64:$checked);
  let assemblyFormat = "$offset `,` $count `,` $size `,` $cause attr-dict";
}

#endif // IDR_CHECK_OPS
