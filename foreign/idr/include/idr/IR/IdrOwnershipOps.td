// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The ops of the owned stage, which idr-rc writes, and the linear
// positions a value enters and is used out of.

#ifndef IDR_OWNERSHIP_OPS
#define IDR_OWNERSHIP_OPS

include "idr/IR/IdrAttrs.td"
include "idr/IR/IdrInterfaces.td"
include "idr/IR/IdrArrayOps.td"
include "mlir/Interfaces/ViewLikeInterface.td"

//===----------------------------------------------------------------------===//
// Ownership
//===----------------------------------------------------------------------===//

// idr-rc makes every reference explicit, in the grades: from then on a
// value that holds references is owned, `!idr.own<T>` (the grade
// (many, own) of T), and holds one reference of its own, which exactly one
// use on every path consumes; or it is a view, plain T, which holds none
// and lives while what it was read from does: a borrowed parameter, a
// field, a match's case argument, an `idr.borrow`, or static data, which
// no count reaches. A module that holds an owned or exclusive value is in
// the owned stage, which its grades say and no attribute restates, and the
// verifier checks the stage's rule there, in each idr.func's region
// verifier (lib/IR/Verify), once its program's stage is `owned`. The ops
// below read and write the counts in cell headers and may free cells, so no
// pass reorders, merges or drops them. Each holds, takes or gives a counted
// reference, and declares how it moves (FlowOpInterface).

def Idr_TokenType : Idr_Type<"Token", "token", [
    DeclareTypeInterfaceMethods<OpAsmTypeInterface, ["getAsmName"]>]> {
  let summary = "the memory of a cell whose fields idr.take moved out, or null";
}

// A value the owned stage counts, at any grade: what its type says it holds
// (isCounted, ValueFactsTypeInterface), never a list of types here. A
// linear field read from a cell that lives on needs a reference of its own,
// so the grade does not matter.
def Idr_CountedType : Type<CPred<"::idr::isCounted($_self)">,
                           "a value the owned stage counts", "::mlir::Type">;

// A value that holds one reference of its own, and a view, which holds
// none.
// The accessors give plain values: idr-rc builds these ops on values it
// grades afterwards.
def Idr_OwnType : Type<CPred<"::idr::isOwned($_self)">, "a value that holds a reference",
                       "::mlir::Type">;
def Idr_ViewType : Type<And<[CPred<"!::idr::isOwned($_self)">, Idr_CountedType.predicate]>,
                        "a value that holds no reference">;

// An op that exists only in the owned stage: before idr-rc nothing counts
// references, so a pass that meets one knows the module's stage.
class Idr_OwnedOp<string mnemonic, list<Trait> traits = []> : Idr_Op<mnemonic, traits> {
  let hasVerifier = 1;
}

def Idr_DupOp : Idr_OwnedOp<"dup", [DeclareOpInterfaceMethods<Idr_FlowOpInterface>]> {
  let summary = "a reference of its own to a value that holds none";
  let description = [{
    The value is a view: what it holds lives on, and the result holds one
    more reference to it. Static data, a small big and an empty slot hold
    no count and are left alone; an unboxed sum adds a reference to each of
    its slots. The result is owned, or exclusive (`-> !idr.excl<T>`) when
    the value is static data that reaches no cell but atoms (a constant
    nullary constructor, or a constant unboxed sum of them), which is in
    every exclusive tree: no take hands out a cell of it.
  }];
  let arguments = (ins Arg<Idr_ViewType, "", [MemRead, MemWrite]>:$value);
  let results = (outs Idr_OwnType:$result);
  let assemblyFormat = [{
    $value attr-dict `:` type($value) custom<OwnedResult>(type($result), ref(type($value)))
  }];
}

def Idr_DropOp : Idr_OwnedOp<"drop", [DeclareOpInterfaceMethods<Idr_FlowOpInterface>]> {
  let summary = "consumes a reference, and frees the value with its last";
  let description = [{
    Freeing a cell drops its fields' references in turn. The drop of a
    token frees the memory of its cell, whose fields idr.take already moved
    out.
  }];
  let arguments = (ins Arg<Idr_OwnType, "", [MemRead, MemWrite, MemFree]>:$value);
  let assemblyFormat = "$value attr-dict `:` type($value)";
}

// A view of an owned value: reads (a field, a tag, a match, a borrowed
// argument) take views, and a view lives only while its owner holds its
// reference: every use of it comes before the owner's consuming use on
// each path. It has no runtime form: the result is the operand's value,
// at a grade that holds no reference.
def Idr_BorrowOp : Idr_Op<"borrow", [Pure, Idr_ResultCarriesOperand,
    DeclareOpInterfaceMethods<ViewLikeOpInterface>,
    DeclareOpInterfaceMethods<Idr_FlowOpInterface>,
    TypesMatchWith<"the view is the value without its reference", "value", "result",
                   "::idr::view($_self)">]> {
  let summary = "a view of an owned value, alive while its owner holds its reference";
  let arguments = (ins Idr_OwnType:$value);
  let results = (outs AnyType:$result);
  let assemblyFormat = "$value attr-dict `:` type($value)";
}

// An owned value given on as owned, whatever it alone reached: an
// exclusive value (`!idr.excl<T>`, which idr-rc proves) given to a position
// that takes an owned one, or a value some view of which took a reference
// of its own (idr.dup) before this, its consuming use. Nothing at runtime.
def Idr_ShareOp : Idr_Op<"share", [Idr_ConsumesOnly<"0">, Idr_ResultCarriesOperand,
    DeclareOpInterfaceMethods<Idr_FlowOpInterface>,
    TypesMatchWith<"the result is the value with its exclusivity forgotten", "value", "result",
                   "::idr::owned(::idr::view($_self))">]> {
  let summary = "gives an owned value on as owned, whatever it alone reached";
  let arguments = (ins Idr_OwnType:$value);
  let results = (outs Idr_OwnType:$result);
  let assemblyFormat = "$value attr-dict `:` type($value)";
}

// A token is always owned: idr.take makes it, idr.reuse or idr.drop
// consumes it.
def Idr_OwnedToken : Type<And<[CPred<"::idr::isOwned($_self)">,
                               CPred<"::llvm::isa<::idr::TokenType>(::idr::unrestricted($_self))">]>,
                          "an owned token", "::mlir::Type"> {
  let builderCall = "::idr::owned(::idr::TokenType::get($_builder.getContext()))";
}

// The constructor is its tag in the result's data type, as idr.con's, and
// so are its holes and their destinations.
def Idr_ReuseOp : Idr_OwnedOp<"reuse", [DeclareOpInterfaceMethods<Idr_FlowOpInterface>]> {
  let summary = "builds a boxed constructor in a token's cell, or in a new one when it is null";
  let arguments = (ins Arg<Idr_OwnedToken, "", [MemWrite]>:$token, Idr_TagAttr:$tag,
                       Variadic<AnyType>:$fields, DefaultValuedAttr<DenseI32ArrayAttr, "{}">:$holes);
  let results = (outs Res<Idr_BoxValue, "", [MemAlloc]>:$result, Variadic<Idr_DestType>:$dests);
  // `idr.reuse %tok !T @Cons(%x : i64, dest)`, as idr.con, in the token's
  // cell.
  let assemblyFormat = [{
    $token type($result) custom<CtorRef>(ref(type($result)), $tag)
    custom<Fields>($fields, type($fields), $holes) attr-dict
    custom<Dests>(type($dests), ref(type($result)), ref($tag), ref($holes))
  }];
  let builders = [
    // The constructor `tag` of `type` built in `token`'s cell with
    // `fields`, and a destination for each of `holes`.
    OpBuilder<(ins "::mlir::Type":$type, "::mlir::Value":$token, "::idr::Tag":$tag,
                   "::mlir::ValueRange":$fields, CArg<"::llvm::ArrayRef<int32_t>", "{}">:$holes)>
  ];
  let extraClassDeclaration = [{
    // The data type of the result.
    ::idr::DataType getDataType();
    // The value given for field `index` of the constructor, or null for a
    // hole; and the destination of a hole, or null for a field given.
    ::mlir::Value getField(unsigned index);
    ::mlir::Value getDest(unsigned index);
  }];
}

// Where a match's scrutinee dies in one of its case regions, which knows
// the constructor: the fields move out of it, so none is counted twice. The
// constructor is its tag in the value's data type.
def Idr_TakeOp : Idr_OwnedOp<"take", [DeclareOpInterfaceMethods<Idr_FlowOpInterface>]> {
  let summary = "consumes a constructor value, each of its fields keeping a reference of its own";
  let description = [{
    The results are the fields of the constructor `tag`, which built the
    value, each with a reference of its own; for a box, a token comes first.
    When the box held the only reference to its cell, the fields move out
    of it with no count changed and the token is the cell, to build another
    constructor in or to free; otherwise each field gets one more reference,
    the box one fewer, and the token is null. An unboxed sum is its fields
    already, so taking it apart changes no count.
  }];
  let arguments = (ins Arg<Idr_OwnType, "", [MemRead, MemWrite, MemFree]>:$value,
                       Idr_TagAttr:$tag);
  let results = (outs Variadic<AnyType>:$results);
  // `idr.take %v : !idr.own<!T> @Cons -> (!idr.own<!idr.token>, i64)`
  let assemblyFormat = [{
    $value `:` type($value) custom<CtorRef>(ref(type($value)), $tag) attr-dict
    `->` custom<ResultTypes>(type($results))
  }];
  let extraClassDeclaration = [{
    // The token, for a box; null for an unboxed sum.
    ::mlir::Value getToken();
    ::mlir::ResultRange getFields();
    // The data type of the value.
    ::idr::DataType getDataType();
  }];
}

// Takes over the fresh reference of a buffer memref.alloc made, whose
// result is a plain memref: the owned stage's one way into a grade for an
// allocation of upstream's. Nothing at runtime.
def Idr_OwnAdoptOp : Idr_Op<"own.adopt", [Pure, DeclareOpInterfaceMethods<Idr_FlowOpInterface>,
    TypesMatchWith<"the result is the buffer owned", "memref", "result",
                   "::idr::owned($_self)">]> {
  let summary = "takes over the fresh reference of a buffer memref.alloc made";
  let arguments = (ins AnyMemRef:$memref);
  let results = (outs Idr_OwnType:$result);
  let assemblyFormat = "$memref attr-dict `:` type($memref)";
  let hasVerifier = 1;
}

// Hands an owned value's reference to the memref.store that writes it,
// whose value is the plain carrier: the value at the plain permission, its
// quantity kept, so that the store, whose element has no grade, refuses a
// linear one rather than lose its quantity. Nothing at runtime: the store
// releases the element it overwrites and the value moves in.
def Idr_OwnGiveOp : Idr_Op<"own.give", [DeclareOpInterfaceMethods<Idr_FlowOpInterface>,
    DeclareOpInterfaceMethods<MemoryEffectsOpInterface>,
    TypesMatchWith<"the result is the value without its reference", "value", "result",
                   "::idr::atPermission($_self, ::idr::Permission::Plain)">]> {
  let summary = "hands an owned value's reference to the store that writes it";
  let arguments = (ins Idr_OwnType:$value);
  let results = (outs AnyType:$result);
  let assemblyFormat = "$value attr-dict `:` type($value)";
  let hasVerifier = 1;
}

//===----------------------------------------------------------------------===//
// Linearity
//===----------------------------------------------------------------------===//

// The two ops that move a value into and out of a linear type. Each gives
// the value at another quantity (Idr_ResultCarriesOperand), as a new value
// allocated on a resource of its own: an allocation is never merged with
// another (two entries of one value stay two linear values) and is removed
// when unused. Both lower to nothing. An entry used at once, or
// a use entered at once, is the value itself: nothing ran in the linear
// position, and each value that remains keeps its type, so the fold loses
// no quantity. A closure or a suspension holding a linear value is the
// exception: its type does not say that it is used once, so the pair it
// passed stays unless what takes the use takes it once. What is left of a
// binder once inlining has joined its two sides is such a pair, and it
// would hide the value from every fold.

// Idris lets any value fill a quantity-1 binder: what enters is used once
// from then on.
// Neither hides the value from an analysis: the integer range of what
// enters is that of what is used.
def Idr_LinEnterOp : Idr_Op<"lin.enter", [Idr_ResultCarriesOperand,
    DeclareOpInterfaceMethods<Idr_FlowOpInterface>,
    DeclareOpInterfaceMethods<OpAsmOpInterface, ["getAsmResultNames"]>,
    TypesMatchWith<"the operand is the value at any quantity", "result", "value",
                   "::idr::atQuantity($_self, ::idr::Quantity::Many)">,
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRangesFromOptional"]>]> {
  let summary = "a value handed to a linear position";
  let arguments = (ins AnyType:$value);
  let results = (outs Res<Idr_LinType, "", [MemAlloc<Idr_LinResource>]>:$result);
  let assemblyFormat = "$value attr-dict `:` qualified(type($result))";
  let hasFolder = 1;
}

// The one use of a linear value, where it becomes an ordinary one.
def Idr_LinUseOp : Idr_Op<"lin.use", [Idr_ResultCarriesOperand,
    DeclareOpInterfaceMethods<Idr_FlowOpInterface>,
    TypesMatchWith<"the result is the value at any quantity", "linear", "result",
                   "::idr::atQuantity($_self, ::idr::Quantity::Many)">,
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRangesFromOptional"]>]> {
  let summary = "the one use of a linear value";
  let arguments = (ins Idr_LinType:$linear);
  let results = (outs Res<AnyType, "", [MemAlloc<Idr_LinResource>]>:$result);
  let assemblyFormat = "$linear attr-dict `:` qualified(type($linear))";
  let hasFolder = 1;
}

#endif // IDR_OWNERSHIP_OPS
