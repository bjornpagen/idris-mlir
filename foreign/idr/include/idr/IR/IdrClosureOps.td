// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The closures and suspensions of the idr dialect, what runs them, and the
// writes of a memo cell that a force's dispatch makes.

#ifndef IDR_CLOSURE_OPS
#define IDR_CLOSURE_OPS

include "idr/IR/IdrAttrs.td"
include "idr/IR/IdrInterfaces.td"

// A suspension's value and the value it holds, and a memo cell's forced
// state and the value settled in it, are one carrier: a grade either has
// beside it is the reference's own, which counting gives each reference.
defvar Idr_SameCarrier = "[](::mlir::Type a, ::mlir::Type b) { "
                         "return ::idr::unrestricted(a) == ::idr::unrestricted(b); }";

// A closure or a suspension holds its captures, so it is used as often as
// they may be: at quantity one exactly when one of them is, and plain
// otherwise. Its type says so, and the linearity verifier counts its one
// use as any linear value's.
def Idr_LinearWhenACaptureIs : PredOpTrait<
    "its result is at quantity one exactly when a capture is",
    CPred<"(::idr::quantityOf($result.getType()) == ::idr::Quantity::One) == "
          "::llvm::any_of($captures.getTypes(), [](::mlir::Type t) { "
          "return ::idr::quantityOf(t) == ::idr::Quantity::One; })">>;

// A closure, plain or at quantity one (Idr_LinearWhenACaptureIs).
def Idr_FnValue : Idr_AtAnyGrade<"::idr::FnType", "a closure at any grade">;

//===----------------------------------------------------------------------===//
// Closures
//===----------------------------------------------------------------------===//

// A closure takes its captures over. A world is never one: it passes only
// as an argument or a result.
def Idr_ClosureOp : Idr_Op<"closure", [Idr_ConsumesOnly, Idr_LinearWhenACaptureIs,
    DeclareOpInterfaceMethods<SymbolUserOpInterface>,
    DeclareOpInterfaceMethods<Idr_FlowOpInterface>,
    DeclareOpInterfaceMethods<OpAsmOpInterface, ["getAsmResultNames"]>]> {
  let summary = "a closure of a function: its leading parameters are the captures";
  let arguments = (ins FlatSymbolRefAttr:$callee, Variadic<Idr_Capture>:$captures);
  let results = (outs Idr_FnValue:$result);
  let assemblyFormat = [{
    $callee `(` $captures `)` attr-dict `:` functional-type($captures, $result)
  }];
  let hasFolder = 1;
}

// Builds the cell, which takes the captures over, none of them a world.
// Does not run the function: a force does, the first one, or every one for
// a label that is `by_name`. Folding to #idr.closure keeps one constant for
// every use, the same attribute a closure uses, at this type.
def Idr_SuspendOp : Idr_Op<"suspend", [Idr_ConsumesOnly, Idr_LinearWhenACaptureIs,
    DeclareOpInterfaceMethods<SymbolUserOpInterface>,
    DeclareOpInterfaceMethods<Idr_FlowOpInterface>,
    DeclareOpInterfaceMethods<OpAsmOpInterface, ["getAsmResultNames"]>]> {
  let summary = "a suspension of a function: every parameter is a capture";
  let arguments = (ins FlatSymbolRefAttr:$callee, Variadic<Idr_Capture>:$captures);
  let results = (outs Idr_LazyValue:$result);
  let assemblyFormat = [{
    $callee `(` $captures `)` attr-dict `:` functional-type($captures, $result)
  }];
  let hasFolder = 1;
}

// A suspension already evaluated: the cell holds its operand, forced, so
// forcing it computes nothing and a force of it folds to the value. It
// takes its operand over, as idr.suspend takes its captures, and a world is
// never held; building it runs nothing. idr-defunctionalize makes it
// idr.con of the memo sum's forced state.
def Idr_DelayOp : Idr_Op<"delay", [Idr_ConsumesOnly,
    TypesMatchWith<"its value is the suspension's carrier", "result", "value",
                   "::llvm::cast<::idr::LazyType>(::idr::unrestricted($_self)).getValue()",
                   Idr_SameCarrier>,
    DeclareOpInterfaceMethods<Idr_FlowOpInterface>,
    DeclareOpInterfaceMethods<OpAsmOpInterface, ["getAsmResultNames"]>]> {
  let summary = "a suspension already evaluated: it holds its operand";
  let arguments = (ins Idr_Capture:$value);
  let results = (outs Idr_LazyValue:$result);
  let assemblyFormat = "$value attr-dict `:` type($value) `->` type($result)";
}

// Reads the cell of a suspension, before idr-defunctionalize: after it a
// force is a call of its memo sum's dispatch, which idr.memo.enter and
// idr.memo.settle write the cell in. Not a call of a shared suspension:
// that would run the body at every use. A suspension with this one use is
// the call, at this point. A force is strict, as a call is: its first entry
// runs a function nothing here bounds, which may crash, not return, or
// reach output, so it writes the crash, divergence and IO resources, each
// ordered with output as a call that may do it is, and is never hoisted
// onto a path that did not force (it is not speculatable). The write that
// shares the value is the force's own, not a second effect. Whether it
// takes its cell over is where it is, its operand's last use, as for a
// match's scrutinee, not a fact of the op, so it does not declare
// consumption. A force of an evaluated suspension folds to its value where
// the types are equal. Its result is the suspension's value up to grade,
// said as a predicate: TypesMatchWith from the suspension to the result
// would have ODS infer the result's type and add InferTypeOpInterface,
// whose check compares the types exactly.
def Idr_ForceOp : Idr_Op<"force", [Idr_RunsLabelsOpInterface,
    MemoryEffects<[MemWrite<Idr_CrashResource>, MemWrite<Idr_DivergenceResource>,
                   MemWrite<Idr_IOResource>]>,
    PredOpTrait<"its result is the suspension's carrier",
        CPred<Idr_SameCarrier # "(::llvm::cast<::idr::LazyType>(::idr::unrestricted("
              "$suspension.getType())).getValue(), $result.getType())">>,
    DeclareOpInterfaceMethods<Idr_FlowOpInterface>,
    DeclareOpInterfaceMethods<OpAsmOpInterface, ["getAsmResultNames"]>]> {
  let summary = "the value of a suspension, computed on the first force and shared";
  let arguments = (ins Idr_LazyValue:$suspension);
  let results = (outs AnyType:$result);
  let assemblyFormat = "$suspension attr-dict `:` type($suspension) `->` type($result)";
  let hasFolder = 1;
  let hasCanonicalizer = 1;
  let extraClassDeclaration = [{
    ::mlir::Value getLabelCarrier() { return getSuspension(); }
  }];
}

// The callee is a value, so the effects are unknown. The arguments are
// taken over, as a call's are. A closure at quantity one is applied as it
// is: the types it is compared with are its carrier's. idr-defunctionalize
// makes each a dispatch on its key's sum, so none is left after it.
def Idr_ApplyOp : Idr_Op<"apply", [CallOpInterface, Idr_RunsLabelsOpInterface,
    TypesMatchWith<"callee input types match argument types", "callee", "args",
                   "::llvm::cast<::idr::FnType>(::idr::unrestricted($_self)).getInputs()",
                   "::idr::sameCarriers">,
    TypesMatchWith<"callee result types match result types", "callee", "results",
                   "::llvm::cast<::idr::FnType>(::idr::unrestricted($_self)).getResults()",
                   "::idr::sameCarriers">,
    DeclareOpInterfaceMethods<Idr_FlowOpInterface>,
    DeclareOpInterfaceMethods<OpAsmOpInterface, ["getAsmResultNames"]>]> {
  let summary = "applies a closure to arguments";
  let arguments = (ins Idr_FnValue:$callee, Variadic<AnyType>:$args,
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
    ::mlir::Value getLabelCarrier() { return getCallee(); }
  }];
}

//===----------------------------------------------------------------------===//
// Memo cells
//===----------------------------------------------------------------------===//

// The cell of a memo sum, which the dispatch of a force reads and writes: a
// view, plain before idr-rc and borrowed after it. A memo cell is the one
// cell that changes while references to it live, and only through these
// ops, each a write of the cell.
def Idr_MemoCell : Type<And<[
    CPred<"::llvm::isa<::idr::BoxType>(::idr::unrestricted($_self))">,
    CPred<"::llvm::cast<::idr::BoxType>(::idr::unrestricted($_self)).getData().isMemo()">,
    CPred<"!::idr::isOwned($_self)">]>,
    "a view of the box of a memo sum", "::mlir::Type">;

// The cell's force has begun: its state becomes Running, so a force that
// reaches the cell again before this one settles it finds the loop. The
// label's captures were read before it; the label's function runs after.
def Idr_MemoEnterOp : Idr_Op<"memo.enter", [DeclareOpInterfaceMethods<Idr_FlowOpInterface>]> {
  let summary = "marks a memo cell's force as running";
  let arguments = (ins Arg<Idr_MemoCell, "", [MemWrite]>:$cell);
  let assemblyFormat = "$cell attr-dict `:` type($cell)";
}

// The cell's force has its value: its state becomes Forced, holding it,
// and every later force reads it. The value moves into the cell, and is
// what the Forced state holds: the one field the body's rules give that
// state, in the memo sum the cell's type is of.
def Idr_MemoSettleOp : Idr_Op<"memo.settle", [
    TypesMatchWith<"its value is the carrier the cell's forced state holds", "cell", "value",
                   "[](::mlir::Type t) { ::idr::DataType memo = "
                   "::llvm::cast<::idr::BoxType>(::idr::unrestricted(t)).getData(); "
                   "return memo.getCtor(memo.getForcedTag()).fields.front(); }($_self)",
                   Idr_SameCarrier>,
    DeclareOpInterfaceMethods<Idr_FlowOpInterface>]> {
  let summary = "stores a memo cell's value, its force done";
  let arguments = (ins Arg<Idr_MemoCell, "", [MemWrite]>:$cell, AnyType:$value);
  let assemblyFormat = "$cell `,` $value attr-dict `:` type($cell) `,` type($value)";
}

#endif // IDR_CLOSURE_OPS
