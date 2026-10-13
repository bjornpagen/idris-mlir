// The ops of the owned stage, which idr-rc writes, and the linear
// positions a value enters and is used out of.

#ifndef IDR_OWNERSHIP_OPS
#define IDR_OWNERSHIP_OPS

include "idr/IR/IdrAttrs.td"
include "idr/IR/IdrInterfaces.td"
include "idr/IR/IdrArrayOps.td"

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
// verifier (lib/IR/Verify). The ops
// below read and write the counts in cell headers and may free cells, so no
// pass reorders, merges or drops them.

def Idr_TokenType : Idr_Type<"Token", "token", [
    DeclareTypeInterfaceMethods<OpAsmTypeInterface, ["getAsmName"]>]> {
  let summary = "the memory of a cell whose fields idr.take moved out, or null";
}

// The values that hold references: a string, a big or natural (a small one
// holds none), a box, a closure, a token, an array, and an unboxed sum with
// a slot of any of these; at any grade, since a linear field read from a
// cell that lives on needs a reference of its own.
def Idr_CountedValueType : AnyTypeOf<[Idr_DataType, Idr_BoxType, Idr_FnType, Idr_LazyType,
                                      Idr_StrType, Idr_BigType, Idr_NatType, Idr_TokenType,
                                      Idr_ArrayType]>;
def Idr_CountedType : AnyTypeOf<[Idr_CountedValueType,
    Type<And<[CPred<"::llvm::isa<::idr::QType>($_self)">,
              SubstLeaves<"$_self", "::idr::unrestricted($_self)",
                          Idr_CountedValueType.predicate>]>,
         "a graded value that holds references">]>;

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

def Idr_DupOp : Idr_OwnedOp<"dup"> {
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

def Idr_DropOp : Idr_OwnedOp<"drop", [Idr_Consumes<"0">]> {
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
// each path. It has no runtime form.
def Idr_BorrowOp : Idr_Op<"borrow", [Pure,
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
def Idr_ShareOp : Idr_Op<"share", [Idr_ConsumesOnly<"0">,
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

def Idr_ReuseOp : Idr_OwnedOp<"reuse", [Idr_Consumes<"0, 1">,
    DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "builds a boxed constructor in a token's cell, or in a new one when it is null";
  let arguments = (ins Arg<Idr_OwnedToken, "", [MemWrite]>:$token, SymbolRefAttr:$ctor,
                       Variadic<AnyType>:$fields);
  let results = (outs Res<Idr_BoxValue, "", [MemAlloc]>:$result);
  let assemblyFormat = [{
    $token $ctor `(` $fields `)` attr-dict `:` functional-type(operands, $result)
  }];
}

// Where a match's scrutinee dies in one of its case regions, which knows
// the constructor: the fields move out of it, so none is counted twice.
def Idr_TakeOp : Idr_OwnedOp<"take", [Idr_Consumes<"0">,
    DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "consumes a constructor value, each of its fields keeping a reference of its own";
  let description = [{
    The results are the fields of `ctor`, which built the value, each with
    a reference of its own; for a box, a token comes first. When the box
    held the only reference to its cell, the fields move out of it with no
    count changed and the token is the cell, to build another constructor
    in or to free; otherwise each field gets one more reference, the box
    one fewer, and the token is null. An unboxed sum is its fields already,
    so taking it apart changes no count.
  }];
  let arguments = (ins Arg<Idr_OwnType, "", [MemRead, MemWrite, MemFree]>:$value,
                       SymbolRefAttr:$ctor);
  let results = (outs Variadic<AnyType>:$results);
  let assemblyFormat = "$value $ctor attr-dict `:` type($value) `->` custom<ResultTypes>(type($results))";
  let extraClassDeclaration = [{
    // The token, for a box; null for an unboxed sum.
    ::mlir::Value getToken();
    ::mlir::ResultRange getFields();
  }];
}

//===----------------------------------------------------------------------===//
// Linearity
//===----------------------------------------------------------------------===//

// The two ops that move a value into and out of a linear type. Each makes
// a new value, allocated on a resource of its own: an allocation is never
// merged with another (two entries of one value stay two linear values) and
// is removed when unused. Both lower to nothing. An entry used at once, or
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
def Idr_LinEnterOp : Idr_Op<"lin.enter", [Idr_Consumes<"0">,
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
def Idr_LinUseOp : Idr_Op<"lin.use", [Idr_Consumes<"0">,
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
