// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
//===- IdrBytecode.td - The idr dialect's bytecode -------*- tablegen -*-===//
//
// The bytecode records of the idr dialect's types and attributes, in
// upstream's DSL (mlir/IR/BytecodeBase.td): mlir-tblgen -gen-bytecode
// writes the C++ reader and writer, and idris-mlir-tblgen -gen-idris-bytecode
// the frontend's encoders, from these records alone, so an entry has one
// layout. A type or attribute without a record is written as its text, the
// bytecode's own fallback: a data type among them, whose text is its name
// (Idr_DataType), its body once in the program's table.
//
//===----------------------------------------------------------------------===//

#ifndef IDR_BYTECODE
#define IDR_BYTECODE

include "mlir/IR/BytecodeBase.td"

// An enum of the ODS, written as its case's value. A value that is no case
// is refused (readEnum). `enumName` is the enum's name, in C++ and in the
// Idris syntax module alike.
class Idr_Enum<string name> :
  WithParser <"succeeded(readEnum($_reader, $_var, ::idr::symbolize" # name # "))",
  WithBuilder<"$_args",
  WithPrinter<"$_writer.writeVarInt(static_cast<uint64_t>($_getter))",
  WithType   <"::idr::" # name>>>> { string enumName = name; }
// An attribute a record may lack: none, or its entry.
def Idr_OptionalAttr : WithParser<"succeeded($_reader.readOptionalAttribute($_var))",
  WithPrinter<"$_writer.writeOptionalAttribute($_getter)",
  WithType<"::mlir::Attribute", Attribute>>>;
def String : WithParser<"succeeded($_reader.readString($_var))",
  WithBuilder<"$_args", WithPrinter<"$_writer.writeOwnedString($_getter)",
  WithType<"::llvm::StringRef">>>>;

// The generated builder falls back to `get` for a type whose `getChecked`
// takes a context, so the type that verifies names its own.
def QType : DialectType<(type Idr_Enum<"Quantity">:$quantity,
  Idr_Enum<"Permission">:$permission, Type:$value, Idr_Enum<"Lifetime">:$lifetime)> {
  let cBuilder = "QType::getChecked([&]() { return reader.emitError(); }, context, $_args)"; }
def FnType : DialectType<(type WithType<"::mlir::FunctionType", Type>:$function_type)>;
def LazyType : DialectType<(type Type:$value)>;
def BoxType : DialectType<(type WithType<"::idr::DataType", Type>:$data)>;
def DestType : DialectType<(type WithType<"::idr::BoxType", Type>:$value)>;
def IdrDialectTypes : DialectTypes<"Idr"> {
  let elems = [QType, FnType, LazyType, BoxType, DestType]; }

// The dag operator of a composite's members.
def record;

// The program's table of data types (Idr_DataTableAttr): one row per data
// type, its name and its body. A constructor's role is its case, then the
// function a label names and whether it is by name, none and 0 for every
// other role; the reader refuses a row that says otherwise
// (DataTableAttr::fromRows). Each member is a getter of the record it is
// read into (idr::TableCtor, idr::TableMember, IdrDialect.h).
def TableCtor : CompositeBytecode<"::idr::TableCtor"> {
  dag members = (record String:$name, Idr_Enum<"CtorRole">:$role, Idr_OptionalAttr:$label,
                 VarInt:$by_name, Array<Type>:$fields);
  let cBuilder = "::idr::TableCtor{name, role, label, by_name, fields}"; }
def TableMember : CompositeBytecode<"::idr::TableMember"> {
  dag members = (record String:$name, Idr_Enum<"SumKind">:$kind, Array<TableCtor>:$ctors,
                 Idr_OptionalAttr:$instance);
  let cBuilder = "::idr::TableMember{name, kind, ctors, instance}"; }
def DataTable : DialectAttribute<(attr Array<TableMember>:$rows)> {
  let cType = "::idr::DataTableAttr";
  let cBuilder = "::idr::DataTableAttr::fromRows(reader, context, rows)"; }
def IdrDialectAttributes : DialectAttributes<"Idr"> { let elems = [DataTable]; }

#endif // IDR_BYTECODE
