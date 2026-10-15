// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A data type's body: the rules a body is checked by when it is set, so
// that every type has them and no op that meets one checks them again; and
// how a body is written and read, the way LLVM writes an identified struct,
// which ends a cycle of types at its name.

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/DialectImplementation.h"
#include "llvm/ADT/STLExtras.h"

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
    if (!llvm::is_contained(rule.roles, ctor.role))
      return emitError() << "the constructor @" << ctorName << " of the "
                         << stringifySumKind(body.kind) << " sum \"" << typeName << "\" is "
                         << stringifyCtorRole(ctor.role);
    // A label is found by its function, and nothing else has one.
    if ((ctor.role == CtorRole::Label) != static_cast<bool>(ctor.fn))
      return emitError() << "the constructor @" << ctorName << " of \"" << typeName
                         << "\" names a function exactly when it is a label";
    // Only a label runs at a force, so only a memo sum's label is by name.
    if (ctor.byName && !(body.kind == SumKind::Memo && ctor.role == CtorRole::Label))
      return emitError() << "the constructor @" << ctorName << " of \"" << typeName
                         << "\" is by_name, which only a label of a memo sum is";
  }
  for (RoleOnce once : rule.once) {
    auto inRole = [&](const Ctor &ctor) { return ctor.role == once.role; };
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
        body.ctors, [](const Ctor &ctor) { return ctor.role == CtorRole::ListCons; });
    Type tail = unrestricted(cons->fields[1]);
    if (auto box = dyn_cast<BoxType>(tail))
      tail = box.getData();
    if (tail != type)
      return emitError() << "the list \"" << typeName
                         << "\" is a nil, and a cons of an element and the list";
  }
  return success();
}

// `<"T">` inside the type's own body, `<"T", kind [@C(fields) role, ...]
// instance #idr.instance<...>>` everywhere else: the way LLVM writes an
// identified struct, which ends a cycle of types at its name. A plain
// constructor writes no role, and a label writes its function after it.
void DataType::print(AsmPrinter &printer) const {
  FailureOr<AsmPrinter::CyclicPrintReset> cyclic = printer.tryStartCyclicPrint(*this);
  printer << '<';
  printer.printString(getName());
  if (failed(cyclic)) {
    printer << '>';
    return;
  }
  printer << ", " << stringifySumKind(getKind()) << " [";
  llvm::interleaveComma(getCtors(), printer, [&](const Ctor &ctor) {
    printer.printSymbolName(ctor.name.getValue());
    printer << '(';
    llvm::interleaveComma(ctor.fields, printer);
    printer << ')';
    if (ctor.role != CtorRole::Plain)
      printer << ' ' << stringifyCtorRole(ctor.role);
    if (ctor.fn)
      printer << ' ' << ctor.fn;
    if (ctor.byName)
      printer << " by_name";
  });
  printer << ']';
  if (InstanceAttr instance = getInstance())
    printer << " instance " << instance;
  printer << '>';
}

Type DataType::parse(AsmParser &parser) {
  MLIRContext *context = parser.getContext();
  SMLoc nameLoc = parser.getCurrentLocation();
  std::string identifier;
  if (parser.parseLess() || parser.parseString(&identifier))
    return {};
  if (identifier.empty()) {
    parser.emitError(nameLoc, "expects a data type to have a name");
    return {};
  }
  DataType type = get(context, identifier);
  // The name alone: only where the type's own body is being read, which
  // has the body to come.
  if (succeeded(parser.parseOptionalGreater())) {
    if (succeeded(parser.tryStartCyclicParse(type))) {
      parser.emitError(nameLoc, "a data type is written without its body only inside its own body");
      return {};
    }
    return type;
  }
  FailureOr<AsmParser::CyclicParseReset> cyclic = parser.tryStartCyclicParse(type);
  if (failed(cyclic)) {
    parser.emitError(nameLoc) << "the data type \"" << identifier
                              << "\" is written with its body inside its own body";
    return {};
  }
  if (parser.parseComma())
    return {};
  SMLoc kindLoc = parser.getCurrentLocation();
  StringRef keyword;
  if (parser.parseKeyword(&keyword))
    return {};
  std::optional<SumKind> kind = symbolizeSumKind(keyword);
  if (!kind) {
    parser.emitError(kindLoc, "expects the kind of sum: plain, list, in_place, closures or memo");
    return {};
  }
  SMLoc bodyLoc = parser.getCurrentLocation();
  // The constructors' fields, which the body views until it is set.
  std::vector<SmallVector<Type>> fields;
  SmallVector<Ctor> ctors;
  static constexpr StringRef roles[] = {"nil", "cons", "label", "running", "forced"};
  auto parseCtor = [&]() -> ParseResult {
    Ctor ctor;
    SmallVector<Type> &ctorFields = fields.emplace_back();
    if (parser.parseSymbolName(ctor.name) ||
        parser.parseCommaSeparatedList(AsmParser::Delimiter::Paren, [&]() {
          return parser.parseType(ctorFields.emplace_back());
        }))
      return failure();
    StringRef role;
    if (succeeded(parser.parseOptionalKeyword(&role, roles)))
      ctor.role = *symbolizeCtorRole(role);
    if (ctor.role == CtorRole::Label && parser.parseAttribute(ctor.fn))
      return failure();
    ctor.byName = succeeded(parser.parseOptionalKeyword("by_name"));
    ctors.push_back(ctor);
    return success();
  };
  if (parser.parseCommaSeparatedList(AsmParser::Delimiter::Square, parseCtor))
    return {};
  InstanceAttr instance;
  if (succeeded(parser.parseOptionalKeyword("instance")) && parser.parseAttribute(instance))
    return {};
  if (parser.parseGreater())
    return {};
  for (auto [ctor, ctorFields] : llvm::zip_equal(ctors, fields))
    ctor.fields = ctorFields;
  if (failed(type.setBody([&] { return parser.emitError(bodyLoc); }, {*kind, ctors, instance})))
    return {};
  return type;
}
