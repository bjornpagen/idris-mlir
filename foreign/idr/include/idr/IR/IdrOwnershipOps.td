// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The ops idr-rc writes: the cells a constructor is built in and the ops
// of the owned stage; and the linear positions a value enters and is used
// out of.

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

// An op that idr-rc writes and nothing before it meets: a cell, made in its
// first step, or a count, in the owned stage it sets.
class Idr_OwnedOp<string mnemonic, list<Trait> traits = []> : Idr_Op<mnemonic, traits>;

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
  let hasVerifier = 1;
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
def Idr_BorrowOp : Idr_Op<"borrow", [Pure, Idr_ResultCarriesOperand, Idr_SameValue,
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
// It keeps the value and forgets its exclusivity, so it is no
// Idr_SameValue: a source followed through it would prove a shared cell
// exclusive.
def Idr_ShareOp : Idr_Op<"share", [Idr_ConsumesOnly, Idr_ResultCarriesOperand,
    DeclareOpInterfaceMethods<Idr_FlowOpInterface>,
    TypesMatchWith<"the result is the value with its exclusivity forgotten", "value", "result",
                   "::idr::owned(::idr::view($_self))">]> {
  let summary = "gives an owned value on as owned, whatever it alone reached";
  let arguments = (ins Idr_OwnType:$value);
  let results = (outs Idr_OwnType:$result);
  let assemblyFormat = "$value attr-dict `:` type($value)";
}

// A token is always owned: idr.take makes it, and idr.cell.recycle or
// idr.drop consumes it. Every op that holds one writes its type.
def Idr_OwnedToken : Type<And<[CPred<"::idr::isOwned($_self)">,
                               CPred<"::llvm::isa<::idr::TokenType>(::idr::unrestricted($_self))">]>,
                          "an owned token", "::mlir::Type">;

//===----------------------------------------------------------------------===//
// Cells
//===----------------------------------------------------------------------===//

// A box's value is built in memory once idr-rc has run, as bufferization
// makes a tensor's memory explicit in buffers: before idr-rc idr.con builds
// the value, and idr-rc's first step rewrites each idr.con that builds a
// cell (buildsCell) into the op that gives the cell and idr.cell.init,
// which fills it. Each source of a cell is an op of its own, with its
// effect declared, as memref.alloc, memref.alloca and memref.realloc are:
// a later step that places the cell elsewhere replaces only that op, and
// the init that names the cell stays what it is. The source writes the
// cell's header; the init writes its fields.

// `!idr.cell<!idr.box<!L>, @Cons>`: the box whose cell it is, then the
// constructor by its name in the box's data type (lib/IR/OpsOwnership.cpp).
def Idr_CellType : Idr_Type<"Cell", "cell"> {
  let summary = "the memory of one cell of a constructor, its header written, its fields not yet";
  let description = [{
    A cell has no grade: it holds no reference until idr.cell.init writes
    its fields, and its one use is that init, as its type alone says. A
    constructor that is an atom has no cell (buildsCell), so no cell type
    names one.
  }];
  let parameters = (ins "::idr::BoxType":$box, Idr_TagParameter:$tag);
  let hasCustomAssemblyFormat = 1;
  let genVerifyDecl = 1;
}

def Idr_CellNewOp : Idr_OwnedOp<"cell.new", [DeclareOpInterfaceMethods<Idr_FlowOpInterface>]> {
  let summary = "a fresh cell on the heap, its header written";
  let description = [{
    The memory of one cell of the constructor its type names, allocated on
    the heap as memref.alloc allocates a buffer, with the constructor's
    header written. idr-rc's first step makes one for each idr.con that
    builds a cell, so it exists only from idr-rc on.

    `%c = idr.cell.new : !idr.cell<!idr.box<!L>, @Cons>`
  }];
  let results = (outs Res<Idr_CellType, "", [MemAlloc<DefaultResource, 0, FullEffect>]>:$cell);
  let assemblyFormat = "attr-dict `:` qualified(type($cell))";
}

def Idr_CellStackOp : Idr_OwnedOp<"cell.stack", [DeclareOpInterfaceMethods<Idr_FlowOpInterface>]> {
  let summary = "a cell in its function's frame, its header written";
  let description = [{
    The memory of one cell, in the frame of the idr.func that holds it (its
    AutomaticAllocationScope), freed when the function returns, as
    memref.alloca allocates a buffer, with the constructor's header
    written. idr-rc puts it in place of an idr.cell.new whose cell never
    leaves its frame, before reuse is decided, so it exists only from
    idr-rc on and a stack cell is never recycled.

    `%c = idr.cell.stack : !idr.cell<!idr.box<!L>, @Cons>`
  }];
  let results = (outs Res<Idr_CellType, "",
      [MemAlloc<AutomaticAllocationScopeResource, 0, FullEffect>]>:$cell);
  let assemblyFormat = "attr-dict `:` qualified(type($cell))";
}

def Idr_CellRecycleOp : Idr_OwnedOp<"cell.recycle", [DeclareOpInterfaceMethods<Idr_FlowOpInterface>]> {
  let summary = "the cell of a token, or a fresh cell on the heap when it is null";
  let description = [{
    The token's cell given up, and a cell for the constructor the result's
    type names, its header written, as memref.realloc gives up its source
    and allocates its result: the same memory when the token holds the cell
    of a box whose take moved its fields out, and a fresh cell on the heap
    when the token is null, the take of a shared box. Which cell may be
    recycled for which constructor is the Reuses analysis's decision, which
    the owned stage's verifier holds against the take the token comes from;
    this op does not decide it. idr-rc puts it in place of an idr.cell.new
    in the owned stage, where tokens exist.

    `%c = idr.cell.recycle %t : !idr.own<!idr.token> -> !idr.cell<!idr.box<!L>, @Cons>`
  }];
  let arguments = (ins Arg<Idr_OwnedToken, "", [MemFreeAt<0, FullEffect>]>:$token);
  let results = (outs Res<Idr_CellType, "", [MemAlloc<DefaultResource, 1, FullEffect>]>:$cell);
  let assemblyFormat = "$token `:` type($token) attr-dict `->` qualified(type($cell))";
}

// Its results are verified before its flow is read (traits verify in this
// order): a hole the inference refuses has no destination to flow through.
def Idr_CellInitOp : Idr_OwnedOp<"cell.init", [InferTypeOpAdaptorWithIsCompatible,
    PredOpTrait<"its fields are its cell's constructor's, the holes aside, each at the field's type or owned",
                CPred<"::idr::detail::fillsCell(::llvm::cast<::idr::CellInitOp>(&$_op))">>,
    DeclareOpInterfaceMethods<Idr_FlowOpInterface>]> {
  let summary = "writes the fields of a cell's constructor into it, giving the box";
  let description = [{
    Each field given is written into the cell, which this consumes, and the
    result is the box that refers to it: the value the cell now holds, as
    memref.store writes a buffer and bufferization.to_tensor gives a
    buffer's value. A field given owned moves its reference into the cell.
    A hole is a field written later, exactly once, through its destination,
    which the op gives in the order of the holes; only a box's field is a
    hole (idr-trmc makes them). The result types are a function of the
    cell's type and the holes (InferTypeOpInterface). The box is inferred
    plain, as idr-rc's first step builds it, and is held at the grade its
    value has: at the quantity Idris gave the constructor, and owned or
    exclusive once counted. Its type is written `-> T` unless it is the
    owned box. It exists only from idr-rc on.

    `%b, %d = idr.cell.init %c : !idr.cell<!idr.box<!L>, @Cons> (%x : i64, dest)`
  }];
  let arguments = (ins Arg<Idr_CellType, "", [MemWrite]>:$cell, Variadic<AnyType>:$fields,
                       DefaultValuedAttr<Idr_HolePositions, "{}">:$holes);
  let results = (outs Idr_BoxValue:$result, Variadic<Idr_DestType>:$dests);
  let assemblyFormat = [{
    $cell `:` qualified(type($cell)) custom<Fields>($fields, type($fields), $holes) attr-dict
    custom<CellResult>(type($result), ref(type($cell)))
    custom<CellDests>(type($dests), ref(type($cell)), ref($holes))
  }];
  let skipDefaultBuilders = 1;
  let builders = [
    // The box `cell` holds with `fields`, inferred plain, and a
    // destination for each of `holes`.
    OpBuilder<(ins "::mlir::Value":$cell, "::mlir::ValueRange":$fields,
                   CArg<"::llvm::ArrayRef<int32_t>", "{}">:$holes)>,
    // The same, the box held as `result`: a linear constructor's value at
    // its quantity, or a box counting has graded.
    OpBuilder<(ins "::mlir::Type":$result, "::mlir::Value":$cell, "::mlir::ValueRange":$fields,
                   CArg<"::llvm::ArrayRef<int32_t>", "{}">:$holes)>
  ];
  let extraClassDeclaration = [{
    // The data type of the box, and the constructor its cell is of.
    ::idr::DataType getDataType();
    ::idr::Tag getTag();
    // The value given for field `index` of the constructor, or null for a
    // hole; and the destination of a hole, or null for a field given.
    ::mlir::Value getField(unsigned index);
    ::mlir::Value getDest(unsigned index);
    // The destination of each hole of `cell`'s constructor; a hole out of
    // range or at a field that is no box gives none (inference refuses it).
    static ::llvm::SmallVector<::mlir::Type> destTypes(CellType cell, ::llvm::ArrayRef<int32_t> holes);
  }];
}

//===----------------------------------------------------------------------===//
// Taking a constructor value apart
//===----------------------------------------------------------------------===//

// Where a match's scrutinee dies in one of its case regions, which knows
// the constructor: the fields move out of it, so none is counted twice. The
// constructor is its tag in the value's data type. A value whose
// constructor has a cell (buildsCell) is taken apart by idr.take, which
// reads and may free the cell; any other by idr.unpack, which reads no
// memory. Each infers its results: the fields, each read at the value's
// grade times its own, as a match binds it, and owned where it holds
// references; the commit may write an owned one exclusive.

def Idr_TakeOp : Idr_OwnedOp<"take", [InferTypeOpAdaptorWithIsCompatible,
    DeclareOpInterfaceMethods<Idr_FlowOpInterface>]> {
  let summary = "consumes a box with a cell, each of its fields keeping a reference of its own";
  let description = [{
    The results are a token, then the fields of the constructor `tag`,
    which built the value, each with a reference of its own, loaded from
    the box's cell as memref.load reads a buffer. When the box held the
    only reference to its cell, the fields move out of it with no count
    changed and the token is the cell, to recycle or to free; otherwise
    each field gets one more reference, the box one fewer, and the token is
    null. It exists only in the owned stage.

    `%w:3 = idr.take %l : !idr.own<!idr.box<!L>> @Cons -> (!idr.own<!idr.token>, i64, !idr.own<!idr.box<!L>>)`
  }];
  let arguments = (ins Arg<Idr_OwnType, "", [MemRead, MemWrite, MemFree]>:$value, Idr_TagAttr:$tag);
  let results = (outs Idr_OwnedToken:$token, Variadic<AnyType>:$fields);
  let assemblyFormat = [{
    $value `:` type($value) custom<CtorRef>(ref(type($value)), $tag) attr-dict
    `->` `(` type($token) (`,` type($fields)^)? `)`
  }];
  let skipDefaultBuilders = 1;
  let builders = [OpBuilder<(ins "::mlir::Value":$value, "::idr::Tag":$tag)>];
  let extraClassDeclaration = [{ ::idr::DataType getDataType(); }];
}

def Idr_UnpackOp : Idr_OwnedOp<"unpack", [Idr_ConsumesOnly, InferTypeOpAdaptorWithIsCompatible,
    DeclareOpInterfaceMethods<Idr_FlowOpInterface>]> {
  let summary = "consumes a constructor value with no cell of its own, giving its fields";
  let description = [{
    An unboxed sum is its fields already, held in its slots, so its fields
    move out with no count changed, as tensor.extract reads a value and no
    memory; an atom, a box of a constructor without fields, is static and
    gives nothing. What it consumes is its only effect (Idr_ConsumesOnly),
    so an atom's unpack, which has no result, is never removed as dead while
    its owned value would stay unconsumed. It exists only in the owned
    stage.

    `%f:2 = idr.unpack %s : !idr.own<!S> @Pair -> (i64, !idr.own<!idr.str>)`
  }];
  let arguments = (ins Idr_OwnType:$value, Idr_TagAttr:$tag);
  let results = (outs Variadic<AnyType>:$fields);
  let assemblyFormat = [{
    $value `:` type($value) custom<CtorRef>(ref(type($value)), $tag) attr-dict
    `->` custom<ResultTypes>(type($fields))
  }];
  let skipDefaultBuilders = 1;
  let builders = [OpBuilder<(ins "::mlir::Value":$value, "::idr::Tag":$tag)>];
  let extraClassDeclaration = [{ ::idr::DataType getDataType(); }];
}

// Takes over the fresh reference of a buffer memref.alloc made, whose
// result is a plain memref: the owned stage's one way into a grade for an
// allocation of upstream's. Nothing at runtime.
def Idr_OwnAdoptOp : Idr_Op<"own.adopt", [Pure, Idr_NoRuntimeForm,
    DeclareOpInterfaceMethods<Idr_FlowOpInterface>,
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
def Idr_OwnGiveOp : Idr_Op<"own.give", [Idr_NoRuntimeForm, DeclareOpInterfaceMethods<Idr_FlowOpInterface>,
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
def Idr_LinEnterOp : Idr_Op<"lin.enter", [Idr_ResultCarriesOperand, Idr_SameValue,
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
def Idr_LinUseOp : Idr_Op<"lin.use", [Idr_ResultCarriesOperand, Idr_SameValue,
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
