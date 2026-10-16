// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The idr dialect's bytecode: the readers and writers mlir-tblgen generates
// from IdrBytecode.td's records, behind the dialect's bytecode interface as
// builtin's are, and what the DSL cannot declare: an enum's value, the
// module's table of data types and a data type's entry, a member of it. A
// data type is written once per module, its body in the table, because its
// text holds the body of every data type it reaches, once per path through
// them. The pinned writer encodes no mutable type, so only the frontend
// writes the table, and this reads it. PIN(bytecode-data-table)

#include "idr/IR/IdrDialect.h"

#include "mlir/Bytecode/BytecodeImplementation.h"
#include "mlir/IR/BuiltinDialect.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/TypeSwitch.h"
#include "llvm/Support/MathExtras.h"
#include "llvm/Support/TypeName.h"

#include <deque>

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

// The codes a field of the table is written with, one per case of what the
// field's type holds: a type that holds no data type is shared as an entry,
// a data type is a member of the table, and a type that holds one is written
// in place, as a record of one of the two dialects the frontend's types come
// from.
enum class FieldCode : uint64_t { Entry = 0, Member = 1, Idr = 2, Builtin = 3 };

// The reader of the table's bodies. A record asks its reader for a type,
// which upstream's reader resolves as an entry, and a field is no entry:
// this reader reads a field where a record asks for a type, and passes every
// other read to the reader it wraps, the table entry's. Through it the
// generated readers of idr's records and builtin's interface read a record
// in a field as they read one in an entry.
class FieldReader final : public DialectBytecodeReader {
public:
  // `tableMembers` are the table's data types, made before any field is read.
  FieldReader(DialectBytecodeReader &reader, ArrayRef<DataType> tableMembers)
      : wrapped(reader), members(tableMembers),
        builtin(cast<BytecodeDialectInterface>(
            static_cast<Dialect &>(*reader.getContext()->getLoadedDialect<BuiltinDialect>()))) {}

  LogicalResult readType(Type &result) override {
    uint64_t code;
    if (failed(wrapped.readVarInt(code)))
      return failure();
    switch (static_cast<FieldCode>(code)) {
    case FieldCode::Entry:
      return wrapped.readType(result);
    case FieldCode::Member: {
      uint64_t index;
      if (failed(wrapped.readVarInt(index)))
        return failure();
      if (index >= members.size())
        return wrapped.emitError() << "expects a member of the table's " << members.size()
                                   << " data types, got member " << index;
      result = members[index];
      return success();
    }
    case FieldCode::Idr:
      result = ::readType(getContext(), *this);
      return success(static_cast<bool>(result));
    case FieldCode::Builtin:
      result = builtin.readType(*this);
      return success(static_cast<bool>(result));
    }
    return wrapped.emitError() << "expects a field code from 0 to 3, got " << code;
  }

  InFlightDiagnostic emitError(const Twine &msg) const override { return wrapped.emitError(msg); }
  InFlightDiagnostic emitWarning(const Twine &msg) const override {
    return wrapped.emitWarning(msg);
  }
  FailureOr<const DialectVersion *> getDialectVersion(StringRef dialectName) const override {
    return wrapped.getDialectVersion(dialectName);
  }
  MLIRContext *getContext() const override { return wrapped.getContext(); }
  uint64_t getBytecodeVersion() const override { return wrapped.getBytecodeVersion(); }
  LogicalResult readAttribute(Attribute &result) override { return wrapped.readAttribute(result); }
  LogicalResult readOptionalAttribute(Attribute &result) override {
    return wrapped.readOptionalAttribute(result);
  }
  LogicalResult readVarInt(uint64_t &result) override { return wrapped.readVarInt(result); }
  LogicalResult readSignedVarInt(int64_t &result) override {
    return wrapped.readSignedVarInt(result);
  }
  FailureOr<APInt> readAPIntWithKnownWidth(unsigned bitWidth) override {
    return wrapped.readAPIntWithKnownWidth(bitWidth);
  }
  FailureOr<APFloat> readAPFloatWithKnownSemantics(const llvm::fltSemantics &semantics) override {
    return wrapped.readAPFloatWithKnownSemantics(semantics);
  }
  LogicalResult readString(StringRef &result) override { return wrapped.readString(result); }
  LogicalResult readBlob(ArrayRef<char> &result) override { return wrapped.readBlob(result); }
  LogicalResult readBool(bool &result) override { return wrapped.readBool(result); }

private:
  FailureOr<AsmDialectResourceHandle> readResourceHandle() override {
    return wrapped.readResourceHandle<AsmDialectResourceHandle>();
  }

  DialectBytecodeReader &wrapped;
  ArrayRef<DataType> members;
  const BytecodeDialectInterface &builtin;
};

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

// Every member is made before any body is read, without its body, so that a
// field names any of them, as the parser makes a data type before reading
// its body; then every body is read, and only then set, in member order,
// each checked as it is set. A read the reader defers fails before any body
// is set, and the reader reads the table again from its start, where `get`
// gives the same members.
LogicalResult DataType::readTable(DialectBytecodeReader &reader, ArrayAttr &table) {
  MLIRContext *context = reader.getContext();
  // Neither the parser nor define makes a data type without a name, so the
  // empty name is taken before the first member is read, and one refusal
  // covers it and a name read twice.
  llvm::DenseSet<StringRef> names{StringRef()};
  SmallVector<DataType> members;
  auto readMember = [&](DataType &member) -> LogicalResult {
    StringRef name;
    if (failed(reader.readString(name)))
      return failure();
    if (!names.insert(name).second)
      return reader.emitError() << "expects the table's data types to have distinct names, "
                                   "none of them empty, got \""
                                << name << "\"";
    member = get(context, name);
    return success();
  };
  if (failed(reader.readList(members, readMember)))
    return failure();

  FieldReader fields(reader, members);
  // Each constructor's fields, which its Ctor views until its body is set:
  // a deque, so that a view stays valid as the next constructors are read.
  std::deque<SmallVector<Type>> fieldStorage;
  auto readCtor = [&](Ctor &ctor) -> LogicalResult {
    StringRef name;
    SmallVector<Type> &ctorFields = fieldStorage.emplace_back();
    if (failed(reader.readString(name)) ||
        failed(readEnum(reader, ctor.role, symbolizeCtorRole)) ||
        failed(reader.readBool(ctor.byName)) || failed(reader.readOptionalAttribute(ctor.fn)) ||
        failed(fields.readTypes(ctorFields)))
      return failure();
    ctor.name = StringAttr::get(context, name);
    ctor.fields = ctorFields;
    return success();
  };
  auto readBody = [&](Body &body) -> LogicalResult {
    return success(succeeded(readEnum(reader, body.kind, symbolizeSumKind)) &&
                   succeeded(reader.readList(body.ctors, readCtor)) &&
                   succeeded(reader.readOptionalAttribute(body.instance)));
  };
  SmallVector<Body> bodies;
  if (failed(reader.readListWithKnownSize(bodies, members.size(), readBody)))
    return failure();

  for (auto [member, body] : llvm::zip_equal(members, bodies))
    if (failed(member.setBody([&] { return reader.emitError(); }, body)))
      return failure();
  table = ArrayAttr::get(context, llvm::map_to_vector(members, [](DataType member) -> Attribute {
                           return TypeAttr::get(member);
                         }));
  return success();
}

// The table and the index are what the entry's bytes name, so both are
// checked here. Whatever data type the table holds has its body: readTable
// makes its table only once every body is set, and the parser and define
// give no data type without one.
Type DataType::member(DialectBytecodeReader &reader, ArrayAttr table, uint64_t index) {
  ArrayRef<Attribute> entries = table.getValue();
  auto entry = index < entries.size() ? dyn_cast<TypeAttr>(entries[index]) : TypeAttr();
  if (auto type = entry ? dyn_cast<DataType>(entry.getValue()) : DataType())
    return type;
  reader.emitError() << "expects a data type's entry to name a data type of its table, got member "
                     << index << " of " << entries.size();
  return {};
}

void idr::detail::addBytecodeInterface(IdrDialect &dialect) {
  dialect.addInterfaces<IdrBytecodeInterface>();
}
