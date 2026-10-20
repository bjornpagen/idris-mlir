// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A data type's body: the rules a body is checked by when it is set, so
// that every type has them and no op that meets one checks them again; and
// how a body is written and read, the way LLVM writes an identified struct,
// which ends a cycle of types at its name.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"

#include "mlir/IR/DialectImplementation.h"
#include "llvm/ADT/STLExtras.h"

#include <cstddef>
#include <utility>
#include <variant>
#include <vector>

using namespace mlir;
using namespace idr;

namespace {

// What each kind of sum is made of: the roles its constructors may play,
// and those it has exactly one constructor in, with the number of fields
// that one has.
struct RoleOnce {
  CtorRole role;
  size_t fields;
};
struct KindRule {
  SmallVector<CtorRole, 3> roles;
  SmallVector<RoleOnce, 2> once;
};

KindRule ruleOf(SumKind kind) {
  switch (kind) {
  case SumKind::Plain:
  case SumKind::InPlace:
    return {{CtorRole::Plain}, {}};
  case SumKind::BaseList:
    return {{CtorRole::ListNil, CtorRole::ListCons},
            {{CtorRole::ListNil, 0}, {CtorRole::ListCons, 2}}};
  case SumKind::Closures:
    return {{CtorRole::Label}, {}};
  case SumKind::Memo:
    return {{CtorRole::Label, CtorRole::Running, CtorRole::Forced},
            {{CtorRole::Running, 0}, {CtorRole::Forced, 1}}};
  }
  llvm_unreachable("a kind of sum");
}

} // namespace

// The rules of a well-formed sum, checked once, when its body is set: so a
// type has them, and no op that meets one checks them again.
LogicalResult DataType::verifyBody(DataType type, function_ref<InFlightDiagnostic()> emitError,
                                   const Body &body) {
  StringRef typeName = type.getName();
  KindRule rule = ruleOf(body.kind);
  llvm::SmallDenseSet<StringAttr, 8> names;
  for (const Ctor &ctor : body.ctors) {
    if (!ctor.name || ctor.name.getValue().empty())
      return emitError() << "the data type \"" << typeName
                         << "\" has a constructor without a name";
    StringRef ctorName = ctor.name.getValue();
    if (!names.insert(ctor.name).second)
      return emitError() << "the data type \"" << typeName << "\" has two constructors @" << ctorName;
    for (Type field : ctor.fields)
      if (!isFieldType(field))
        return emitError() << "the constructor @" << ctorName << " of \"" << typeName
                           << "\" has a field of unsupported type " << field;
    if (!llvm::is_contained(rule.roles, kindOf(ctor.role)))
      return emitError() << "the constructor @" << ctorName << " of the "
                         << stringifySumKind(body.kind) << " sum \"" << typeName << "\" is "
                         << stringifyCtorRole(kindOf(ctor.role));
    // Only a label runs at a force, so only a memo sum's label is by name.
    if (const auto *label = std::get_if<role::Label>(&ctor.role);
        label && label->byName && body.kind != SumKind::Memo)
      return emitError() << "the constructor @" << ctorName << " of \"" << typeName
                         << "\" is by_name, which only a label of a memo sum is";
  }
  for (RoleOnce once : rule.once) {
    auto inRole = [&](const Ctor &ctor) { return kindOf(ctor.role) == once.role; };
    const Ctor *it = llvm::find_if(body.ctors, inRole);
    if (llvm::count_if(body.ctors, inRole) != 1 || it->fields.size() != once.fields)
      return emitError() << "the " << stringifySumKind(body.kind) << " sum \"" << typeName
                         << "\" has one constructor " << stringifyCtorRole(once.role)
                         << ", of " << once.fields << " fields";
  }
  // The string ops walk and build base's list by its shape, which the
  // registry names and this states once: the cons holds an element and the
  // list, which contains itself and so is held in a box once layout::fit
  // has made the boxes.
  if (body.kind == SumKind::BaseList) {
    const Ctor *cons = llvm::find_if(
        body.ctors, [](const Ctor &ctor) { return kindOf(ctor.role) == CtorRole::ListCons; });
    Type tail = unrestricted(cons->fields[1]);
    if (auto box = dyn_cast<BoxType>(tail))
      tail = box.getData();
    if (tail != type)
      return emitError() << "the list \"" << typeName
                         << "\" is a nil, and a cons of an element and the list";
  }
  return success();
}

//===----------------------------------------------------------------------===//
// How a body is written and read
//===----------------------------------------------------------------------===//

// A data type is nominal, so it is written as its name alone wherever it
// occurs, `!idr.data<"T">`, and its body once, as a member of its
// program's table (Idr_DataTableAttr): `"T" = kind [@C(fields) role, ...]
// instance #idr.instance<...>`. A plain constructor writes no role, and a
// label writes its function after its role, then `by_name` when it is.
void DataType::print(AsmPrinter &printer) const {
  printer << '<';
  printer.printString(getName());
  printer << '>';
}

Type DataType::parse(AsmParser &parser) {
  SMLoc nameLoc = parser.getCurrentLocation();
  std::string identifier;
  if (parser.parseLess() || parser.parseString(&identifier) || parser.parseGreater())
    return {};
  if (identifier.empty()) {
    parser.emitError(nameLoc, "expects a data type to have a name");
    return {};
  }
  return get(parser.getContext(), identifier);
}

namespace {

void printBody(AsmPrinter &printer, DataType type) {
  printer << stringifySumKind(type.getKind()) << " [";
  llvm::interleaveComma(type.getCtors(), printer, [&](const Ctor &ctor) {
    printer.printSymbolName(ctor.name.getValue());
    printer << '(';
    llvm::interleaveComma(ctor.fields, printer);
    printer << ')';
    if (CtorRole kind = kindOf(ctor.role); kind != CtorRole::Plain)
      printer << ' ' << stringifyCtorRole(kind);
    if (const auto *label = std::get_if<role::Label>(&ctor.role)) {
      printer << ' ' << label->fn;
      if (label->byName)
        printer << " by_name";
    }
  });
  printer << ']';
  if (InstanceAttr instance = type.getInstance())
    printer << " instance " << instance;
}

// A body read: its constructors' fields in `fields`, which the body views
// until it is set. Failure after the parser's error.
FailureOr<DataType::Body> parseBody(AsmParser &parser, std::vector<SmallVector<Type>> &fields) {
  SMLoc kindLoc = parser.getCurrentLocation();
  StringRef keyword;
  if (parser.parseKeyword(&keyword))
    return failure();
  std::optional<SumKind> kind = symbolizeSumKind(keyword);
  if (!kind)
    return parser.emitError(kindLoc,
                            "expects the kind of sum: plain, list, in_place, closures or memo");
  SmallVector<Ctor> ctors;
  // The roles a constructor writes, every one but plain, which it leaves
  // out: their spellings are the enum's.
  SmallVector<StringRef> roles;
  for (uint32_t value = 0; value <= getMaxEnumValForCtorRole(); ++value)
    if (std::optional<CtorRole> role = symbolizeCtorRole(value); role && *role != CtorRole::Plain)
      roles.push_back(stringifyCtorRole(*role));
  auto parseCtor = [&]() -> ParseResult {
    Ctor ctor;
    SmallVector<Type> &ctorFields = fields.emplace_back();
    if (parser.parseSymbolName(ctor.name) ||
        parser.parseCommaSeparatedList(AsmParser::Delimiter::Paren, [&]() {
          return parser.parseType(ctorFields.emplace_back());
        }))
      return failure();
    StringRef spelled;
    CtorRole played = CtorRole::Plain;
    if (succeeded(parser.parseOptionalKeyword(&spelled, roles)))
      played = *symbolizeCtorRole(spelled);
    ctor.role = emptyRole(played);
    // Only a label has more to read: its function, and whether it is by
    // name.
    if (auto *label = std::get_if<role::Label>(&ctor.role)) {
      if (parser.parseAttribute(label->fn))
        return failure();
      label->byName = succeeded(parser.parseOptionalKeyword("by_name"));
    }
    ctors.push_back(ctor);
    return success();
  };
  if (parser.parseCommaSeparatedList(AsmParser::Delimiter::Square, parseCtor))
    return failure();
  InstanceAttr instance;
  if (succeeded(parser.parseOptionalKeyword("instance")) && parser.parseAttribute(instance))
    return failure();
  for (auto [ctor, ctorFields] : llvm::zip_equal(ctors, fields))
    ctor.fields = ctorFields;
  return DataType::Body{*kind, ctors, instance};
}

} // namespace

//===----------------------------------------------------------------------===//
// The program's table of data types
//===----------------------------------------------------------------------===//

void DataTableAttr::print(AsmPrinter &printer) const {
  printer << '<';
  llvm::interleave(
      getMembers(), printer,
      [&](DataType member) {
        printer << "\n  ";
        printer.printString(member.getName());
        printer << " = ";
        printBody(printer, member);
      },
      ",");
  if (!getMembers().empty())
    printer << '\n';
  printer << '>';
}

Attribute DataTableAttr::parse(AsmParser &parser, Type) {
  MLIRContext *context = parser.getContext();
  SMLoc loc = parser.getCurrentLocation();
  SmallVector<DataType> members;
  auto parseMember = [&]() -> ParseResult {
    SMLoc nameLoc = parser.getCurrentLocation();
    std::string name;
    if (parser.parseString(&name) || parser.parseEqual())
      return failure();
    if (name.empty())
      return parser.emitError(nameLoc, "expects a data type to have a name");
    DataType member = DataType::get(context, name);
    SMLoc bodyLoc = parser.getCurrentLocation();
    std::vector<SmallVector<Type>> fields;
    FailureOr<DataType::Body> body = parseBody(parser, fields);
    if (failed(body) ||
        failed(member.setBody([&] { return parser.emitError(bodyLoc); }, *body)))
      return failure();
    members.push_back(member);
    return success();
  };
  if (parser.parseCommaSeparatedList(AsmParser::Delimiter::LessGreater, parseMember))
    return {};
  return getChecked([&] { return parser.emitError(loc); }, context, ArrayRef<DataType>(members));
}

LogicalResult DataTableAttr::verify(function_ref<InFlightDiagnostic()> emitError,
                                    ArrayRef<DataType> members) {
  for (auto [index, member] : llvm::enumerate(members)) {
    if (!member.bodySet())
      return emitError() << "the data type \"" << member.getName() << "\" has no body";
    if (index > 0 && members[index - 1].getName() >= member.getName())
      return emitError() << "the data types are in name order, each once, and \""
                         << members[index - 1].getName() << "\" comes before \""
                         << member.getName() << "\"";
  }
  return success();
}

bool DataTableAttr::holds(DataType data) const {
  ArrayRef<DataType> members = getMembers();
  const DataType *at = llvm::lower_bound(
      members, data, [](DataType a, DataType b) { return a.getName() < b.getName(); });
  return at != members.end() && *at == data;
}

void DataTableAttr::walkMembers(DataTableAttr table, function_ref<void(Type)> walk) {
  for (DataType member : table.getMembers())
    walk(member);
}

// A replacer replaces a member as it replaces any occurrence of the type:
// one that boxes a data type wherever it occurs hands back a box of it,
// and the member is the data type, whichever it became.
DataTableAttr DataTableAttr::replaced(DataTableAttr table, ArrayRef<Type> members) {
  SmallVector<DataType> kept;
  for (Type member : members) {
    DataType data = dataTypeOf(member);
    assert(data && "a member of the table is replaced by a type that is no data type");
    kept.push_back(data);
  }
  llvm::sort(kept, [](DataType a, DataType b) { return a.getName() < b.getName(); });
  kept.erase(llvm::unique(kept), kept.end());
  return get(table.getContext(), ArrayRef<DataType>(kept));
}

DataTableAttr DataTableAttr::with(ArrayRef<DataType> types) const {
  SmallVector<DataType> members(getMembers());
  llvm::append_range(members, types);
  llvm::sort(members, [](DataType a, DataType b) { return a.getName() < b.getName(); });
  members.erase(llvm::unique(members), members.end());
  if (members.size() == getMembers().size())
    return *this;
  return get(getContext(), ArrayRef<DataType>(members));
}
