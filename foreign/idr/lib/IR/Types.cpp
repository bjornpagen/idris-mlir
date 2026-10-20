// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The dialect's types: their generated definitions and their spellings,
// with the storage of a data type, which they need complete, and what
// touches it: the sealing of a group of types, which writes each body with
// what its values hold once, and define, which seals the types a pass
// makes; and the canonical forms of !idr.q. How a body is checked and
// written is lib/IR/DataBody.cpp's, what a value holds
// lib/IR/ValueFacts.cpp's, and the literals and the printer's names of the
// types lib/IR/TypeLiterals.cpp's.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"

#include "mlir/IR/DialectImplementation.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/TypeSwitch.h"
#include "llvm/Support/ErrorHandling.h"

#include <array>

using namespace mlir;
using namespace idr;

//===----------------------------------------------------------------------===//
// The storage of a data type
//===----------------------------------------------------------------------===//

namespace idr::detail {

// A sealing: the body and what a value of the type holds, written together.
struct Sealing {
  const DataType::Body &body;
  Held held;
};

// A data type is identified by its name, the key, which holds no type. The
// rest is written once, whole, when the type's group is sealed, as an LLVM
// identified struct's body is set (TypeDetail.h's mutate): the body and what
// a value holds, under the uniquer's lock for that one write, and read after
// it by every thread with no lock at all. A second sealing succeeds only
// with the same body. The constructors and their fields live in the
// context's allocator, as the type does, and so do an index of the tags by
// name and the tag of each role a sum has one of.
struct DataTypeStorage : TypeStorage {
  using KeyTy = StringRef;

  explicit DataTypeStorage(StringRef name) : identifier(name) {}

  bool operator==(const KeyTy &key) const { return key == identifier; }
  static llvm::hash_code hashKey(const KeyTy &key) { return llvm::hash_value(key); }
  static DataTypeStorage *construct(TypeStorageAllocator &allocator, const KeyTy &key) {
    return new (allocator.allocate<DataTypeStorage>()) DataTypeStorage(allocator.copyInto(key));
  }
  KeyTy getAsKey() const { return identifier; }

  LogicalResult mutate(TypeStorageAllocator &allocator, Sealing sealing) {
    const DataType::Body &body = sealing.body;
    if (defined)
      return success(kind == body.kind && instance == body.instance &&
                     ctors == ArrayRef<Ctor>(body.ctors));
    SmallVector<Ctor> copied;
    copied.reserve(body.ctors.size());
    for (const Ctor &ctor : body.ctors)
      copied.push_back({ctor.name, allocator.copyInto(ctor.fields), ctor.role});
    ctors = allocator.copyInto(ArrayRef<Ctor>(copied));
    SmallVector<Tag> order = llvm::to_vector(llvm::map_range(
        llvm::seq<uint32_t>(0, static_cast<uint32_t>(ctors.size())),
        [](uint32_t tag) { return Tag{tag}; }));
    llvm::sort(order, [&](Tag a, Tag b) { return name(a) < name(b); });
    byName = allocator.copyInto(ArrayRef<Tag>(order));
    for (auto [tag, ctor] : llvm::enumerate(ctors))
      roleTags[static_cast<size_t>(kindOf(ctor.role))] = Tag{static_cast<uint32_t>(tag)};
    kind = body.kind;
    instance = body.instance;
    held = sealing.held;
    defined = true;
    return success();
  }

  // The name of the constructor `tag`.
  StringRef name(Tag tag) const { return ctors[static_cast<uint32_t>(tag)].name.getValue(); }

  StringRef identifier;
  bool defined = false;
  SumKind kind = SumKind::Plain;
  ArrayRef<Ctor> ctors;
  InstanceAttr instance;
  // The tags, in the order of their constructors' names.
  ArrayRef<Tag> byName;
  // By role, the tag of the last constructor in that role, which is the
  // one for a role the body's rules say a sum has one of; none for a role
  // no constructor plays.
  std::array<std::optional<Tag>, getMaxEnumValForCtorRole() + 1> roleTags{};
  // What a value holds.
  Held held = Held::Nothing;
};

} // namespace idr::detail

#define GET_TYPEDEF_CLASSES
#include "idr/IR/IdrTypes.cpp.inc"

#include "idr/IR/IdrTypeInterfaces.cpp.inc"

void IdrDialect::registerTypes() {
  addTypes<
#define GET_TYPEDEF_LIST
#include "idr/IR/IdrTypes.cpp.inc"
      >();
  registerValueFacts();
}

//===----------------------------------------------------------------------===//
// Data types
//===----------------------------------------------------------------------===//

DataType DataType::get(MLIRContext *context, StringRef identifier) {
  return Base::get(context, identifier);
}

StringRef DataType::getName() const { return getImpl()->identifier; }
// A type is read only once it is whole: a name alone has nothing to read.
SumKind DataType::getKind() const {
  assert(isDefined() && "a sealed data type");
  return getImpl()->kind;
}

ArrayRef<Ctor> DataType::getCtors() const {
  assert(isDefined() && "a sealed data type");
  return getImpl()->ctors;
}

Held DataType::getHeld() const {
  assert(isDefined() && "a sealed data type");
  return getImpl()->held;
}

const Ctor &DataType::getCtor(Tag tag) const {
  assert(isDefined() && "a sealed data type");
  auto position = static_cast<uint32_t>(tag);
  assert(position < getImpl()->ctors.size() && "a constructor of the data type");
  return getImpl()->ctors[position];
}

InstanceAttr DataType::getInstance() const {
  assert(isDefined() && "a sealed data type");
  return getImpl()->instance;
}

std::optional<Tag> DataType::getTag(StringRef ctor) const {
  assert(isDefined() && "a sealed data type");
  const detail::DataTypeStorage &storage = *getImpl();
  const Tag *it = llvm::partition_point(storage.byName,
                                        [&](Tag tag) { return storage.name(tag) < ctor; });
  if (it == storage.byName.end() || storage.name(*it) != ctor)
    return std::nullopt;
  return *it;
}

Tag DataType::roleTag(CtorRole role) const {
  std::optional<Tag> tag = getImpl()->roleTags[static_cast<size_t>(role)];
  assert(tag && kindOf(getCtor(*tag).role) == role &&
         "a role the data type has one constructor of");
  return *tag;
}

bool DataType::isAtom(Tag tag) const { return !isMemo() && getCtor(tag).fields.empty(); }

void DataType::walkLabels(DataType type, function_ref<void(Attribute)> walk) {
  for (const Ctor &ctor : type.getCtors())
    if (const auto *label = std::get_if<role::Label>(&ctor.role))
      walk(label->fn);
}

// A body is set once, so a label's function cannot be replaced inside the
// type: the type with the new label is another type, and so is every type
// whose body holds it, which only a remap of the whole module makes
// (DataRemap, given the rename). A replacer that reaches a label here,
// renaming it as replaceAllSymbolUses would, would leave every value of
// the type naming the old function.
Type DataType::replaceLabels(DataType type, ArrayRef<Attribute> labels) {
  ArrayRef<Attribute> rest = labels;
  for (const Ctor &ctor : type.getCtors()) {
    const auto *label = std::get_if<role::Label>(&ctor.role);
    if (!label)
      continue;
    if (rest.empty() || rest.front() != label->fn)
      llvm::reportFatalInternalError(
          "the label @" + ctor.name.getValue() + " of the data type \"" + type.getName() +
          "\" renamed in place; a renamed label's data types are remade (DataRemap)");
    rest = rest.drop_front();
  }
  return type;
}

bool DataType::isDefined() const { return getImpl()->defined; }

LogicalResult DataType::seal(ArrayRef<DataDefinition> group,
                             function_ref<InFlightDiagnostic(size_t member)> emitError) {
  llvm::SmallDenseSet<DataType, 8> members;
  for (auto [index, member] : llvm::enumerate(group)) {
    if (!members.insert(member.type).second)
      return emitError(index) << "the data type \"" << member.type.getName()
                              << "\" has another body already";
    if (failed(verifyBody(member.type, [&] { return emitError(index); }, member.body)))
      return failure();
  }
  FailureOr<SmallVector<Held>> held = solveHeld(group, emitError);
  if (failed(held))
    return failure();
  // A member sealed already is checked first, so that a refused group
  // writes nothing.
  for (auto [index, member] : llvm::enumerate(group)) {
    const detail::DataTypeStorage &storage = *member.type.getImpl();
    if (storage.defined &&
        (storage.kind != member.body.kind || storage.instance != member.body.instance ||
         storage.ctors != ArrayRef<Ctor>(member.body.ctors)))
      return emitError(index) << "the data type \"" << member.type.getName()
                              << "\" has another body already";
  }
  for (auto [member, answer] : llvm::zip_equal(group, *held))
    (void)DataType(member.type).mutate(detail::Sealing{member.body, answer});
  return success();
}

FailureOr<DataType>
Declarations::define(StringRef identifier,
                     function_ref<FailureOr<DataType::Body>(DataType self)> body) {
  auto emitError = [&] { return program.emitError() << "internal error: "; };
  if (identifier.empty())
    return emitError() << "a data type has no name";
  DataType type = DataType::get(program.getContext(), identifier);
  ++open;
  FailureOr<DataType::Body> built = body(type);
  --open;
  if (failed(built)) {
    if (open == 0)
      pending.clear();
    return failure();
  }
  Pending &kept = pending.emplace_back();
  kept.definition = {type, {built->kind, {}, built->instance}};
  for (const Ctor &ctor : built->ctors) {
    kept.fields.emplace_back(ctor.fields.begin(), ctor.fields.end());
    kept.definition.body.ctors.push_back({ctor.name, {}, ctor.role});
  }
  if (open > 0)
    return type;
  // The outermost define: every type it and the defines inside it made is
  // whole now, each body held here, and the group is sealed at once.
  SmallVector<DataDefinition> group;
  for (Pending &each : pending) {
    for (auto [ctor, fields] : llvm::zip_equal(each.definition.body.ctors, each.fields))
      ctor.fields = fields;
    group.push_back(each.definition);
  }
  LogicalResult sealed = DataType::seal(group, [&](size_t) { return emitError(); });
  if (succeeded(sealed))
    for (const DataDefinition &each : group)
      made.push_back(each.type);
  pending.clear();
  if (failed(sealed))
    return failure();
  return type;
}

Declarations::~Declarations() { program.declare(made); }

//===----------------------------------------------------------------------===//
// The dialect's spellings of its types
//===----------------------------------------------------------------------===//

namespace {

// The dialect's spellings of a value at a grade, read and written from this
// one table: a grade over any value. Any other grade is the generated
// `!idr.q<quantity, permission, value>`, with `, frame` after the value
// when it is of the frame, as is every grade when written out.
struct Over {
  StringRef keyword;
  Grade grade;
};
constexpr Over overs[] = {{"lin", {Quantity::One, Permission::Plain}},
                          {"own", {Quantity::Many, Permission::Own}},
                          {"excl", {Quantity::Many, Permission::Excl}}};

} // namespace

Type IdrDialect::parseType(DialectAsmParser &parser) const {
  llvm::SMLoc loc = parser.getCurrentLocation();
  MLIRContext *ctx = parser.getContext();
  for (const Over &over : overs)
    if (succeeded(parser.parseOptionalKeyword(over.keyword))) {
      Type value;
      if (parser.parseLess() || parser.parseType(value) || parser.parseGreater())
        return {};
      return QType::getChecked([&] { return parser.emitError(loc); }, ctx, over.grade, value);
    }
  // The generated parser reads the mnemonic itself.
  StringRef mnemonic;
  Type type;
  OptionalParseResult result = generatedTypeParser(parser, &mnemonic, type);
  if (result.has_value())
    return type;
  parser.emitError(loc) << "unknown type `" << mnemonic << "` in dialect `idr`";
  return {};
}

void IdrDialect::printType(Type type, DialectAsmPrinter &printer) const {
  if (auto q = dyn_cast<QType>(type))
    for (const Over &over : overs)
      if (q.getGrade() == over.grade) {
        printer << over.keyword << '<' << q.getValue() << '>';
        return;
      }
  if (failed(generatedTypePrinter(type, printer)))
    llvm_unreachable("a type of the idr dialect");
}

//===----------------------------------------------------------------------===//
// Grades
//===----------------------------------------------------------------------===//

// The canonical forms: a plain type is (many, plain) and is never written
// as a grade; a grade is of a carrier, never of a grade; a type used
// exactly once by its type (the world, a destination, a cell) takes none;
// a tensor, an array value, is at (one, plain) only, the quantity Idris
// proved of it, since bufferization owns its memory; any other grade is of
// a runtime type.
LogicalResult QType::verify(function_ref<InFlightDiagnostic()> emitError, Quantity quantity,
                            Permission permission, Type value, Lifetime lifetime) {
  Grade grade{quantity, permission, lifetime};
  if (grade.plain())
    return emitError() << "expects a grade other than (many, plain), which is the plain type";
  if (isa<QType>(value))
    return emitError() << "expects a grade of a plain type, got one of " << value;
  if (idr::isLinearByType(value))
    return emitError() << "expects no grade of " << value
                       << ", which is used exactly once by its type";
  if (lifetime == Lifetime::Frame && !mayBeFrame(value))
    return emitError() << "expects no frame lifetime of " << value
                       << ", which reaches no cell of a frame";
  if (lifetime == Lifetime::Frame && permission == Permission::Excl)
    return emitError() << "expects no exclusive value of the frame, whose cells the frame lends";
  if (isa<RankedTensorType>(value) && grade != Grade{Quantity::One, Permission::Plain})
    return emitError() << "expects " << value << " at (one, plain)";
  // A runtime type: one a field may have, or a token, which is owned.
  if (!isFieldType(value) && !isa<TokenType>(value))
    return emitError() << "expects a grade of a runtime type, got " << value;
  return success();
}
