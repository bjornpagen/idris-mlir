// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The idr dialect's bytecode: the readers and writers mlir-tblgen generates
// from IdrBytecode.td's records, behind the dialect's bytecode interface as
// builtin's are, and what the DSL cannot declare: an enum's value, and the
// program's table of data types between its rows and its members.

#include "idr/IR/IdrDialect.h"

#include "mlir/Bytecode/BytecodeImplementation.h"
#include "mlir/IR/BuiltinDialect.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/TypeSwitch.h"
#include "llvm/Support/MathExtras.h"
#include "llvm/Support/TypeName.h"

#include <utility>
#include <variant>

using namespace mlir;
using namespace idr;

namespace {

// An enum of the ODS, written as its case's value. A value that is no case
// is refused here, so no reader of the type meets one.
template <typename E>
LogicalResult readEnum(DialectBytecodeReader &reader, E &result,
                       std::optional<E> (*symbolize)(uint32_t)) {
  uint64_t value;
  if (failed(reader.readVarInt(value)))
    return failure();
  // The ODS numbers its cases in 32 bits: a wider value is no case, and
  // narrowed it could name one.
  std::optional<E> known =
      llvm::isUInt<32>(value) ? symbolize(static_cast<uint32_t>(value)) : std::nullopt;
  if (!known)
    return reader.emitError() << "expects a case of " << llvm::getTypeName<E>() << ", got "
                              << value;
  result = *known;
  return success();
}

#include "idr/IR/IdrBytecode.cpp.inc"

// The dialect's bytecode interface, as builtin's: the generated readers and
// writers of IdrBytecode.td's records, and every other type and attribute
// as its text.
struct IdrBytecodeInterface final : BytecodeDialectInterface {
  using BytecodeDialectInterface::BytecodeDialectInterface;

  Attribute readAttribute(DialectBytecodeReader &reader) const override {
    return ::readAttribute(getContext(), reader);
  }
  LogicalResult writeAttribute(Attribute attr, DialectBytecodeWriter &writer) const override {
    return ::writeAttribute(attr, writer);
  }
  Type readType(DialectBytecodeReader &reader) const override {
    return ::readType(getContext(), reader);
  }
  LogicalResult writeType(Type type, DialectBytecodeWriter &writer) const override {
    return ::writeType(type, writer);
  }
};

} // namespace

SmallVector<TableMember> DataTableAttr::getRows() const {
  SmallVector<TableMember> rows;
  for (DataType member : getMembers()) {
    TableMember row{member.getName(), member.getKind(), {}, member.getInstance()};
    for (const Ctor &ctor : member.getCtors()) {
      TableCtor each{ctor.name.getValue(), kindOf(ctor.role), {}, 0,
                     SmallVector<Type>(ctor.fields)};
      if (const auto *label = std::get_if<role::Label>(&ctor.role)) {
        each.label = label->fn;
        each.byName = label->byName;
      }
      row.ctors.push_back(std::move(each));
    }
    rows.push_back(std::move(row));
  }
  return rows;
}

// A row's fields are already types: an entry of its own each, read by
// name, so a body may name any member, made before or after it.
DataTableAttr DataTableAttr::fromRows(DialectBytecodeReader &reader, MLIRContext *context,
                                      ArrayRef<TableMember> rows) {
  auto emitError = [&] { return reader.emitError(); };
  // The members are read as names and bodies, the fields viewed in the
  // rows, then sealed at once: a body may hold any member.
  SmallVector<DataDefinition> group;
  for (const TableMember &row : rows) {
    if (row.name.empty()) {
      emitError() << "expects a data type to have a name";
      return {};
    }
    DataType member = DataType::get(context, row.name);
    DataType::Body body{row.kind, {}, {}};
    if (row.instance && !(body.instance = dyn_cast<InstanceAttr>(row.instance))) {
      emitError() << "expects the instance of \"" << row.name << "\" to be #idr.instance, got "
                  << row.instance;
      return {};
    }
    for (const TableCtor &ctor : row.ctors) {
      Role role = emptyRole(ctor.role);
      if (auto *label = std::get_if<role::Label>(&role)) {
        label->fn = dyn_cast_if_present<FlatSymbolRefAttr>(ctor.label);
        if (!label->fn) {
          emitError() << "expects the label @" << ctor.name << " of \"" << row.name
                      << "\" to name its function";
          return {};
        }
        label->byName = ctor.byName != 0;
      } else if (ctor.label || ctor.byName != 0) {
        emitError() << "expects no function and no by_name on @" << ctor.name << " of \""
                    << row.name << "\", which is no label";
        return {};
      }
      body.ctors.push_back({StringAttr::get(context, ctor.name), ctor.fields, role});
    }
    group.push_back({member, std::move(body)});
  }
  if (failed(DataType::seal(group, [&](size_t) { return emitError(); })))
    return {};
  SmallVector<DataType> members =
      llvm::to_vector(llvm::map_range(group, [](const DataDefinition &each) { return each.type; }));
  return getChecked(emitError, context, ArrayRef<DataType>(members));
}

void idr::detail::addBytecodeInterface(IdrDialect &dialect) {
  dialect.addInterfaces<IdrBytecodeInterface>();
}
