// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What may crash or not return in the idr dialect: a crash, a loop that
// may not end, and the guards whose conditions the total ops need.

#ifndef IDR_CHECK_OPS
#define IDR_CHECK_OPS

include "idr/IR/IdrAttrs.td"
include "idr/IR/IdrInterfaces.td"

//===----------------------------------------------------------------------===//
// Crashes and loops
//===----------------------------------------------------------------------===//

// A case the definition does not cover, followed by ub.unreachable.
def Idr_CrashOp : Idr_Op<"crash", [Idr_MayCrash<>]> {
  let summary = "ends the program with a message naming the cause";
  let arguments = (ins StrAttr:$message);
  let assemblyFormat = "$message attr-dict";
}

// A trusted library's crash of a string it computed. The message is the
// string's text. The op does not return; Emit follows it with unreachable.
def Idr_CrashStrOp : Idr_Op<"crash_str", [Idr_CallsRuntime, Idr_MayCrash<>, Idr_Primitive]> {
  let summary = "ends the program with a string's text";
  let arguments = (ins Idr_StrType:$message);
  let assemblyFormat = "$message attr-dict";
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
// is the absence of the guard. A guard folds to its operand where the
// operand shows its condition holds (lib/IR/OpsChecks.cpp), and
// idr-in-bounds erases those it proves where they run. The result of a guard
// with an integer range is the operand's range clamped by the condition.
// `kind` is the guard's ::idr::CheckKind. The operand a guard guards is its
// first, which its folder and its lowering give as its result.
class Idr_CheckOp<string mnemonic, string kind, list<Trait> traits = []>
    : Idr_Op<"check." # mnemonic, !listconcat(traits, [Idr_MayCrash<>,
        DeclareOpInterfaceMethods<Idr_GuardOpInterface>])> {
  // nonzero and nonempty also take their operand's reference over and give
  // it to their result (Idr_Consumes), whose trait offers getEffects too: a
  // guard's effects are its crash's alone.
  let extraClassDeclaration = [{
    using ::idr::MayCrash<false>::Impl<ConcreteOpType>::getEffects;
  }];
  let extraClassDefinition = [{
    std::optional<::llvm::StringRef> $cppClass::getCrashCause() { return getCause(); }
    ::idr::CheckKind $cppClass::getKind() { return ::idr::CheckKind::}] # kind # [{; }
    ::mlir::Value $cppClass::getGuarded() { return getOperation()->getOperand(0); }
  }];
  let hasFolder = 1;
}

def Idr_CheckNonzeroOp : Idr_CheckOp<"nonzero", "Nonzero", [SameOperandsAndResultType,
    Idr_Consumes<"0">,
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  let summary = "the value, which must not be zero, else the program crashes";
  let arguments = (ins AnyTypeOf<[Idr_Int, Idr_BigValue]>:$value, StrAttr:$cause);
  let results = (outs AnyTypeOf<[Idr_Int, Idr_BigValue]>:$checked);
  let assemblyFormat = "$value `,` $cause attr-dict `:` type($value)";
}

def Idr_CheckInBoundsOp : Idr_CheckOp<"in_bounds", "InBounds", [
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  let summary = "the index, which must be at least 0 and below the length, else the program crashes";
  let arguments = (ins I64:$index, I64:$length, StrAttr:$cause);
  let results = (outs I64:$checked);
  let assemblyFormat = "$index `,` $length `,` $cause attr-dict";
}

def Idr_CheckNonemptyOp : Idr_CheckOp<"nonempty", "Nonempty", [SameOperandsAndResultType,
    Idr_Consumes<"0">]> {
  let summary = "the string, which must have at least one byte, else the program crashes";
  let arguments = (ins Idr_StrValue:$str, StrAttr:$cause);
  let results = (outs Idr_StrValue:$checked);
  let assemblyFormat = "$str `,` $cause attr-dict `:` type($str)";
}

def Idr_CheckByteOp : Idr_CheckOp<"byte", "Byte", [
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  let summary = "the value, which must be from 0 to 255, else the program crashes";
  let arguments = (ins I64:$value, StrAttr:$cause);
  let results = (outs I64:$checked);
  let assemblyFormat = "$value `,` $cause attr-dict";
}

def Idr_CheckFiniteOp : Idr_CheckOp<"finite", "Finite"> {
  let summary = "the value, which must be neither NaN nor infinite, else the program crashes";
  let arguments = (ins F64:$value, StrAttr:$cause);
  let results = (outs F64:$checked);
  let assemblyFormat = "$value `,` $cause attr-dict";
}

// The bytes [offset, offset + count) of something of `size` bytes: both at
// least 0, and the end, computed without overflow, at most the size.
def Idr_CheckRangeOp : Idr_CheckOp<"range", "Range", [
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  let summary = "the offset, whose range of `count` bytes must lie in `size`, else the program crashes";
  let arguments = (ins I64:$offset, I64:$count, I64:$size, StrAttr:$cause);
  let results = (outs I64:$checked);
  let assemblyFormat = "$offset `,` $count `,` $size `,` $cause attr-dict";
}

#endif // IDR_CHECK_OPS
