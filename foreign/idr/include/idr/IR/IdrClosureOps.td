// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The closures and suspensions of the idr dialect, and what runs them.

#ifndef IDR_CLOSURE_OPS
#define IDR_CLOSURE_OPS

include "idr/IR/IdrAttrs.td"
include "idr/IR/IdrInterfaces.td"

//===----------------------------------------------------------------------===//
// Closures
//===----------------------------------------------------------------------===//

// A closure takes its captures over.
def Idr_ClosureOp : Idr_Op<"closure", [Idr_ConsumesOnly<"0">,
    DeclareOpInterfaceMethods<SymbolUserOpInterface>,
    DeclareOpInterfaceMethods<OpAsmOpInterface, ["getAsmResultNames"]>]> {
  let summary = "a closure of a function: its leading parameters are the captures";
  let arguments = (ins FlatSymbolRefAttr:$callee, Variadic<AnyType>:$captures);
  let results = (outs Idr_FnType:$result);
  let assemblyFormat = [{
    $callee `(` $captures `)` attr-dict `:` functional-type($captures, $result)
  }];
  let hasFolder = 1;
  let hasVerifier = 1;
}

// Builds the cell, which takes the captures over. Does not run the
// function: a force does, the first one, or every one for a label that is
// `by_name`. Folding to #idr.closure keeps one constant for every use, the
// same attribute a closure uses, at this type.
def Idr_SuspendOp : Idr_Op<"suspend", [Idr_ConsumesOnly<"0">,
    DeclareOpInterfaceMethods<SymbolUserOpInterface>,
    DeclareOpInterfaceMethods<OpAsmOpInterface, ["getAsmResultNames"]>]> {
  let summary = "a suspension of a function: every parameter is a capture";
  let arguments = (ins FlatSymbolRefAttr:$callee, Variadic<AnyType>:$captures);
  let results = (outs Idr_LazyValue:$result);
  let assemblyFormat = [{
    $callee `(` $captures `)` attr-dict `:` functional-type($captures, $result)
  }];
  let hasFolder = 1;
  let hasVerifier = 1;
}

// A suspension already evaluated: the cell holds its operand, forced, so
// forcing it computes nothing and a force of it folds to the value. It
// takes its operand over, as idr.suspend takes its captures; building it
// runs nothing. idr-defunctionalize makes it idr.con of the memo sum's
// forced state.
def Idr_DelayOp : Idr_Op<"delay", [Idr_ConsumesOnly<"0">,
    DeclareOpInterfaceMethods<OpAsmOpInterface, ["getAsmResultNames"]>]> {
  let summary = "a suspension already evaluated: it holds its operand";
  let arguments = (ins AnyType:$value);
  let results = (outs Idr_LazyValue:$result);
  let assemblyFormat = "$value attr-dict `:` type($value) `->` type($result)";
  let hasVerifier = 1;
}

// Reads the cell: a suspension, or, after idr-defunctionalize, the box of a
// memo sum. Not a call of a shared suspension: that would run the body at
// every use. A suspension with this one use is the call, at this point. Its
// effects are the cell's: none for a view of a cell that memoizes, so an
// unused force is erased; the cell freed when the force takes it over; the
// IO resource when a label of its sum is `by_name`, which the sum's type
// says. Not speculatable, so one is not hoisted into a path that did not
// force. Whether it takes its cell over is where it is, its operand's last
// use, as for a match's scrutinee, not a fact of the op, so it does not
// declare consumption. A force of an evaluated suspension folds to its
// value where the types are equal.
def Idr_ForceOp : Idr_Op<"force", [
    DeclareOpInterfaceMethods<MemoryEffectsOpInterface>,
    DeclareOpInterfaceMethods<OpAsmOpInterface, ["getAsmResultNames"]>]> {
  let summary = "the value of a suspension, computed on the first force and shared";
  let arguments = (ins AnyTypeOf<[Idr_LazyValue, Idr_BoxValue]>:$suspension);
  let results = (outs AnyType:$result);
  let assemblyFormat = "$suspension attr-dict `:` type($suspension) `->` type($result)";
  let hasVerifier = 1;
  let hasFolder = 1;
  let hasCanonicalizer = 1;
}

// The callee is a value, so the effects are unknown. The arguments are
// taken over, as a call's are. idr-defunctionalize makes each a dispatch
// on its key's sum, so none is left after it.
def Idr_ApplyOp : Idr_Op<"apply", [CallOpInterface,
    TypesMatchWith<"callee input types match argument types", "callee", "args",
                   "::llvm::cast<FnType>($_self).getInputs()",
                   "::idr::sameCarriers">,
    TypesMatchWith<"callee result types match result types", "callee", "results",
                   "::llvm::cast<FnType>($_self).getResults()",
                   "::idr::sameCarriers">,
    Idr_Consumes<"1">, DeclareOpInterfaceMethods<OpAsmOpInterface, ["getAsmResultNames"]>]> {
  let summary = "applies a closure to arguments";
  let arguments = (ins Idr_FnType:$callee, Variadic<AnyType>:$args,
                       OptionalAttr<DictArrayAttr>:$arg_attrs,
                       OptionalAttr<DictArrayAttr>:$res_attrs);
  let results = (outs Variadic<AnyType>:$results);
  // The parameter and result attributes are written as func.call_indirect
  // writes its own.
  let assemblyFormat = [{
    $callee `(` $args `)`
    oilist<`,`>(
        `arg_attrs` `=` $arg_attrs
      | `res_attrs` `=` $res_attrs
    )
    attr-dict `:` qualified(type($callee))
  }];
  let extraClassDeclaration = [{
    ::mlir::CallInterfaceCallable getCallableForCallee() { return getCallee(); }
    void setCalleeFromCallable(::mlir::CallInterfaceCallable callee) {
      setOperand(0, ::llvm::cast<::mlir::Value>(callee));
    }
    ::mlir::Operation::operand_range getArgOperands() { return getArgs(); }
    ::mlir::MutableOperandRange getArgOperandsMutable() { return getArgsMutable(); }
  }];
}

#endif // IDR_CLOSURE_OPS
