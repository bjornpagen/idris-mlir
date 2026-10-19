// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// How the idr dialect's types are written in bytecode, in upstream's
// bytecode DSL. One file holds the layout: mlir-tblgen -gen-bytecode writes
// the C++ readers and writers of these records (lib/IR/Bytecode.cpp), and
// idris-mlir-tblgen -gen-idris-bytecode the frontend's encoders of the same
// records, so the writer and the reader cannot disagree on a record. An
// entry's first varint is its code, its record's place in its dialect's
// elems. A type no record covers is written as its text. Only
// BytecodeBase.td is included, as upstream's bytecode files do: ODS's own
// `Type` and other names would sit beside the DSL's.

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
def Idr_TableRef : WithType<"::mlir::ArrayAttr", Attribute>;

// A data type: the module's table of data types, and the member's place in
// it. The data type is mutable and the pinned writer asks no dialect to
// encode a mutable type, so the record is only ever read: the C++ writer
// writes a data type as its text, and the frontend writes this record. The
// generator still writes a printer, under a false predicate, whose getters
// must compile; they are constants.
def DataType : DialectTypeNoPrint<(type
  WithGetter<"::mlir::ArrayAttr()", Idr_TableRef>:$table,
  WithGetter<"uint64_t(0)", VarInt>:$index)> {
  let cBuilder = "::idr::DataType::member(reader, table, index)"; }
// The generated builder falls back to `get` for a type whose `getChecked`
// takes a context, so the type that verifies names its own.
def QType : DialectType<(type Idr_Enum<"Quantity">:$quantity,
  Idr_Enum<"Permission">:$permission, Type:$value, Idr_Enum<"Lifetime">:$lifetime)> {
  let cBuilder = "QType::getChecked([&]() { return reader.emitError(); }, context, $_args)"; }
def FnType : DialectType<(type WithType<"::mlir::FunctionType", Type>:$function_type)>;
def LazyType : DialectType<(type Type:$value)>;
def BoxType : DialectType<(type WithType<"::idr::DataType", Type>:$data)>;
def DestType : DialectType<(type WithType<"::idr::BoxType", Type>:$value)>;

// The module's table of data types: every data instance of the program,
// each written once, its body here and every other occurrence a data type
// entry that names its member. Read as an ArrayAttr of a TypeAttr of each
// member, the list of the module's data types. Its layout, which
// DataType::readTable reads and the frontend's writer writes:
//
//     v n, n × s name                    the members, in order
//     n × Body
//     Body:  TableBody: v kind (SumKind), [Ctor], a? instance (#idr.instance)
//     Ctor:  TableCtor: s name, v role (CtorRole; never label: only
//            defunctionalization makes one), [Field]
//     Field: v 0, t       a type that holds no data type: its entry
//            v 1, v k     member k
//            v 2, record  an idr type record, its code then its members
//            v 3, record  a builtin type record, likewise
//
// `v` is a varint, `s` a string by its number in the string
// section, `t` and `a` type and attribute entry numbers, `a?` 0 for none
// and 2n+1 for entry n, `[x]` a count and that many `x`. Inside a field's
// record each type member is a field again and each attribute member an
// entry. A data type inside the table is always a member. Every member is
// made before any body is read, so a field names any of them; no field and
// no entry the table refers to holds a data type's entry, so reading the
// table reads no data type's entry and never the table again.
def DataTable : DialectAttribute<(attr
  WithParser<"succeeded(::idr::DataType::readTable($_reader, $_var))",
  WithBuilder<"$_args", WithPrinter<"", WithType<"::mlir::ArrayAttr">>>>:$table)> {
  let cType = "::mlir::ArrayAttr"; let cBuilder = "table"; let printerPredicate = "false"; }
def IdrDialectTypes : DialectTypes<"Idr"> {
  let elems = [DataType, QType, FnType, LazyType, BoxType, DestType]; }
def IdrDialectAttributes : DialectAttributes<"Idr"> { let elems = [DataTable]; }

class Idr_FieldCode<string caseName> { string name = caseName; }
def FieldEntry : Idr_FieldCode<"Entry">;
def FieldMember : Idr_FieldCode<"Member">;
def FieldIdr : Idr_FieldCode<"Idr">;
def FieldBuiltin : Idr_FieldCode<"Builtin">;
def IdrFieldCodes { list<Idr_FieldCode> codes = [FieldEntry, FieldMember, FieldIdr, FieldBuiltin]; }
def String : WithParser<"succeeded($_reader.readString($_var))",
  WithBuilder<"$_args", WithPrinter<"$_writer.writeOwnedString($_getter)",
  WithType<"::llvm::StringRef">>>>;
def Idr_OptionalAttr : WithParser<"succeeded($_reader.readOptionalAttribute($_var))",
  WithType<"::mlir::Attribute", Attribute>>;
def record;
class Idr_TableRecord;
def TableCtor : CompositeBytecode<"::idr::Ctor">, Idr_TableRecord {
  dag members = (record String:$name, Idr_Enum<"CtorRole">:$role, Array<Type>:$fields); }
def TableBody : CompositeBytecode<"::idr::Body">, Idr_TableRecord {
  dag members = (record Idr_Enum<"SumKind">:$kind, Array<TableCtor>:$ctors,
                 Idr_OptionalAttr:$instance); }

#endif // IDR_BYTECODE
