// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The types of the idr dialect, and the constraints its ops state over them.

#ifndef IDR_TYPES
#define IDR_TYPES

include "idr/IR/IdrBase.td"

//===----------------------------------------------------------------------===//
// Types
//===----------------------------------------------------------------------===//

class Idr_Type<string name, string typeMnemonic, list<Trait> traits = []>
    : TypeDef<Idr_Dialect, name, traits> {
  let mnemonic = typeMnemonic;
}

// Every runtime value type is an element type of memref, so an array of
// values (idr.array.new) is a builtin memref: what the memref and
// bufferization passes work on, with no array type of our own. A type a
// value is commonly of suggests the printer a name for it (getAsmName): `w`
// the world, `s` a string, `n` an Integer or natural, `f` a closure, `lazy`
// a suspension, `tok` a token; a grade suggests its carrier's.
def Idr_DataType : Idr_Type<"Data", "data", [MemRefElementTypeInterface]> {
  let summary = "a value of the unboxed sum declared by idr.data";
  let parameters = (ins "::mlir::FlatSymbolRefAttr":$name);
  let assemblyFormat = "`<` $name `>`";
}

// A value of a boxed type, declared `idr.data @T box`: recursive, or a
// record whose values would make the cells holding them count more
// references than a header can (idr-defunctionalize decides those).
def Idr_BoxType : Idr_Type<"Box", "box", [MemRefElementTypeInterface]> {
  let summary = "a value of the boxed type declared by idr.data ... box";
  let parameters = (ins "::mlir::FlatSymbolRefAttr":$name);
  let assemblyFormat = "`<` $name `>`";
}

// `!idr.fn<(A...) -> R>`: the closure's signature is a function type, held
// as one and written as MLIR writes one (a single result without
// parentheses, which the parser reads either way). A suspension is
// `!idr.lazy<T>`, not a function: defunctionalization would turn a
// function into a sum and the cell would no longer be the one that was
// forced.
def Idr_FnType : Idr_Type<"Fn", "fn", [MemRefElementTypeInterface,
    DeclareTypeInterfaceMethods<OpAsmTypeInterface, ["getAsmName"]>]> {
  let summary = "a closure";
  let parameters = (ins "::mlir::FunctionType":$function_type);
  let assemblyFormat = "`<` $function_type `>`";
  let builders = [
    TypeBuilder<(ins "::llvm::ArrayRef<::mlir::Type>":$inputs,
                     "::llvm::ArrayRef<::mlir::Type>":$results), [{
      return $_get($_ctxt, ::mlir::FunctionType::get($_ctxt, inputs, results));
    }]>
  ];
  let extraClassDeclaration = [{
    ::llvm::ArrayRef<::mlir::Type> getInputs() const { return getFunctionType().getInputs(); }
    ::llvm::ArrayRef<::mlir::Type> getResults() const { return getFunctionType().getResults(); }
  }];
}

// One cell, shared by every reference to it. idr-defunctionalize makes each
// lazy type a memo sum (an idr.data with `memo`, always a box): the
// constructor the cell holds is its state, one per label until it is
// forced, `running` while its force runs, and `forced` with the value after.
// A flag beside the payload could disagree with the state; the constructor
// cannot.
def Idr_LazyType : Idr_Type<"Lazy", "lazy", [MemRefElementTypeInterface,
    DeclareTypeInterfaceMethods<OpAsmTypeInterface, ["getAsmName"]>]> {
  let summary = "a suspension of one value, forced once into this cell";
  let parameters = (ins "::mlir::Type":$value);
  let assemblyFormat = "`<` $value `>`";
  let builders = [
    TypeBuilderWithInferredContext<(ins "::mlir::Type":$value), [{
      return $_get(value.getContext(), value);
    }]>
  ];
}

def Idr_StrType : Idr_Type<"Str", "str", [MemRefElementTypeInterface,
    DeclareTypeInterfaceMethods<OpAsmTypeInterface, ["getAsmName"]>]> {
  let summary = "a string (UTF-8)";
}

def Idr_BigType : Idr_Type<"Big", "big", [MemRefElementTypeInterface,
    DeclareTypeInterfaceMethods<OpAsmTypeInterface, ["getAsmName"]>]> {
  let summary = "an Integer";
}

// Nat, and every type Idris shapes like it (a nullary constructor and a
// unary successor, Fin among them): a big at runtime, never negative. Every
// op that produces one keeps it non-negative (a sum, a product, a
// predecessor of a value that is not zero), and the only way in from an
// Integer, idr.nat.from_big, clamps, so the type itself proves the range.
// Integer range analysis is to seed [0, +inf) from this type in its entry
// state (setToEntryState), for block arguments and results it cannot see
// computed.
def Idr_NatType : Idr_Type<"Nat", "nat", [MemRefElementTypeInterface,
    DeclareTypeInterfaceMethods<OpAsmTypeInterface, ["getAsmName"]>]> {
  let summary = "a natural number: a non-negative big";
}

// The values a big op computes on: an Integer, or a natural where the
// operation keeps naturals natural.
def Idr_BigOrNat : AnyTypeOf<[Idr_BigType, Idr_NatType]>;

// The carrier of the world: the IO world token, which only ever appears
// at grade (one, plain), the type spelled !idr.world. The carrier itself
// is !idr.world_carrier.
def Idr_WorldCarrier : Idr_Type<"World", "world_carrier", [
    DeclareTypeInterfaceMethods<OpAsmTypeInterface, ["getAsmName"]>]> {
  let summary = "the IO world token";
}

// A grade lives in the type, where no pass can drop it. It is a pair
// (u, p) (idr::Grade): u is the quantity Idris proved, one or many, and p
// is what the value owns, plain (nothing to say), borrow, own or excl. A
// plain type T is (many, plain) and is never written as !idr.q. The type
// is `!idr.q<quantity, permission, value>`, and the common grades have
// spellings, which the dialect reads and writes from one table
// (lib/IR/Dialect.cpp): !idr.lin<T> is (one, plain) of T,
// !idr.own<T> and !idr.excl<T> are (many, own) and (many, excl) of T, and
// !idr.world is (one, plain) of the world. A value of quantity one is used
// at most once on every path; its one use is idr.lin.use, or a position
// that is linear itself (a parameter, a field, a capture or a result of
// the same type).
def Idr_QType : Idr_Type<"Q", "q", [
    DeclareTypeInterfaceMethods<OpAsmTypeInterface, ["getAsmName"]>]> {
  let summary = "a value at a grade: its quantity and what it owns";
  let parameters = (ins EnumParameter<Idr_Quantity>:$quantity,
                        EnumParameter<Idr_Permission>:$permission, "::mlir::Type":$value);
  let assemblyFormat = "`<` $quantity `,` $permission `,` $value `>`";
  let genVerifyDecl = 1;
  let builders = [
    TypeBuilder<(ins "::idr::Grade":$grade, "::mlir::Type":$value), [{
      return $_get($_ctxt, grade.quantity, grade.permission, value);
    }]>
  ];
  let extraClassDeclaration = [{
    ::idr::Grade getGrade() const { return {getQuantity(), getPermission()}; }
  }];
}

// The positions that take a grade: the world, and a linear value other
// than the world (one that entered its grade, and is used out of it).
def Idr_WorldType : Type<CPred<"::idr::isWorld($_self)">, "the world", "::idr::QType"> {
  let builderCall = "::idr::world($_builder.getContext())";
}
def Idr_LinType : Type<CPred<"::idr::isLinear($_self)">,
                       "a value of quantity 1 other than the world", "::idr::QType">;

def Idr_SumType : AnyTypeOf<[Idr_DataType, Idr_BoxType]>;
def Idr_Int : AnyTypeOf<[I8, I16, I32, I64]>;

// A value of a type at any grade: what an op that makes one produces,
// plain before idr-rc and owned after it.
class Idr_AtAnyGrade<string cppType, string name>
    : Type<CPred<"::llvm::isa<" # cppType # ">(::idr::unrestricted($_self))">, name, "::mlir::Type">;
def Idr_StrValue : Idr_AtAnyGrade<"::idr::StrType", "a string at any grade">;
def Idr_BigValue : Idr_AtAnyGrade<"::idr::BigType", "an Integer at any grade">;
def Idr_NatValue : Idr_AtAnyGrade<"::idr::NatType", "a natural at any grade">;
def Idr_BigOrNatValue : Idr_AtAnyGrade<"::idr::BigType, ::idr::NatType", "an Integer or a natural at any grade">;
def Idr_BoxValue : Idr_AtAnyGrade<"::idr::BoxType", "a box at any grade">;
// The cell, plain before idr-rc and owned after it. The value inside stays
// the carrier: ownership is the grade of this reference, not a second type.
def Idr_LazyValue : Idr_AtAnyGrade<"::idr::LazyType", "a suspension at any grade">;
def Idr_SumValue : Idr_AtAnyGrade<"::idr::DataType, ::idr::BoxType", "a constructor value at any grade">;
// A constructor value at any quantity that holds no reference of its own:
// what a match takes apart, whose regions bind its fields at its grade.
def Idr_SumView : Type<And<[Idr_SumValue.predicate, CPred<"!::idr::isOwned($_self)">]>,
                       "a constructor value at any quantity, not owned", "::mlir::Type">;

// A destination: a field of a cell built without it (idr.dest.of), the
// word a later write fills.
def Idr_DestType : Idr_Type<"Dest", "dest"> {
  let summary = "a field of a cell built without it, to be written exactly once";
  let parameters = (ins "::mlir::Type":$value);
  let assemblyFormat = "`<` $value `>`";
  let genVerifyDecl = 1;
}

#endif // IDR_TYPES
