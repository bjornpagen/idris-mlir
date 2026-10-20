// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The dialect's types: their generated definitions and their spellings,
// with the storage of a data type, which they need complete, and what
// touches it: the body, made with the type, and the facts of what its
// values hold, kept beside it under the context's lock; the canonical forms
// of !idr.q, the literals of the scalar types of ours, and the names the
// printer gives a value of each type. A graded value takes its carrier's
// name, so a linear string is %s. How a body is checked and written is
// lib/IR/DataBody.cpp's, and what a value holds lib/IR/ValueFacts.cpp's.

#include "idr/IR/IdrDialect.h"

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

// What a value of a data type holds, kept, and asked for: the two other
// changes of a data type's storage, each made under the context's lock.
struct KeptFacts {
  Held held;
};
struct ReadFacts {
  std::optional<Held> &into;
};

// A data type is identified by its name, the key, which holds no type. The
// body is the mutable part, set once as an LLVM identified struct's is
// (TypeDetail.h's mutate): a second setting succeeds only with the same
// body. The constructors and their fields live in the context's allocator,
// as the type does, and so do an index of the tags by name and the tag of
// each role a sum has one of. What a value of the type holds is kept beside
// the body once it is known; it is written and read as the body is set,
// through the uniquer's mutate, under the lock the context takes for it, so
// threads that ask at once each see the facts whole.
struct DataTypeStorage : TypeStorage {
  using KeyTy = StringRef;

  explicit DataTypeStorage(StringRef name) : identifier(name) {}

  bool operator==(const KeyTy &key) const { return key == identifier; }
  static llvm::hash_code hashKey(const KeyTy &key) { return llvm::hash_value(key); }
  static DataTypeStorage *construct(TypeStorageAllocator &allocator, const KeyTy &key) {
    return new (allocator.allocate<DataTypeStorage>()) DataTypeStorage(allocator.copyInto(key));
  }
  KeyTy getAsKey() const { return identifier; }

  LogicalResult mutate(TypeStorageAllocator &allocator, const DataType::Body &body) {
    if (initialized)
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
    initialized = true;
    return success();
  }

  LogicalResult mutate(TypeStorageAllocator &, KeptFacts kept) {
    facts = kept.held;
    return success();
  }

  LogicalResult mutate(TypeStorageAllocator &, ReadFacts read) {
    read.into = facts;
    return success();
  }

  // The name of the constructor `tag`.
  StringRef name(Tag tag) const { return ctors[static_cast<uint32_t>(tag)].name.getValue(); }

  StringRef identifier;
  bool initialized = false;
  SumKind kind = SumKind::Plain;
  ArrayRef<Ctor> ctors;
  InstanceAttr instance;
  // The tags, in the order of their constructors' names.
  ArrayRef<Tag> byName;
  // By role, the tag of the last constructor in that role, which is the
  // one for a role the body's rules say a sum has one of; none for a role
  // no constructor plays.
  std::array<std::optional<Tag>, getMaxEnumValForCtorRole() + 1> roleTags{};
  // What a value holds, none until it is known.
  std::optional<Held> facts;
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
SumKind DataType::getKind() const { return getImpl()->kind; }
ArrayRef<Ctor> DataType::getCtors() const { return getImpl()->ctors; }

const Ctor &DataType::getCtor(Tag tag) const {
  auto position = static_cast<uint32_t>(tag);
  assert(position < getImpl()->ctors.size() && "a constructor of the data type");
  return getImpl()->ctors[position];
}

InstanceAttr DataType::getInstance() const { return getImpl()->instance; }

std::optional<Tag> DataType::getTag(StringRef ctor) const {
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

bool DataType::bodySet() const { return getImpl()->initialized; }

std::optional<Held> DataType::knownFacts() const {
  std::optional<Held> held;
  (void)DataType(*this).mutate(detail::ReadFacts{held});
  return held;
}

void DataType::keepFacts(Held held) const {
  (void)DataType(*this).mutate(detail::KeptFacts{held});
}

LogicalResult DataType::setBody(function_ref<InFlightDiagnostic()> emitError, const Body &body) {
  if (failed(verifyBody(*this, emitError, body)))
    return failure();
  if (failed(Base::mutate(body)))
    return emitError() << "the data type \"" << getName() << "\" has another body already";
  return success();
}

FailureOr<DataType> DataType::define(ProgramOp program, StringRef identifier,
                                     function_ref<FailureOr<Body>(DataType self)> body) {
  auto emitError = [&] { return program.emitError() << "internal error: "; };
  if (identifier.empty())
    return emitError() << "a data type has no name";
  DataType type = get(program.getContext(), identifier);
  FailureOr<Body> made = body(type);
  if (failed(made) || failed(type.setBody(emitError, *made)))
    return failure();
  program.declare(type);
  return type;
}

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

//===----------------------------------------------------------------------===//
// Literals
//===----------------------------------------------------------------------===//

// A string's literal is a string attribute with no type: a typed one
// (`"x" : !idr.str`) is another attribute of the same text, which no
// literal of ours is, so one string has one literal.
bool StrType::isLiteral(Attribute literal) const {
  auto text = dyn_cast<StringAttr>(literal);
  return text && isa<NoneType>(text.getType());
}

ParseResult StrType::parseLiteral(AsmParser &parser, Attribute &literal) const {
  std::string bytes;
  if (parser.parseString(&bytes))
    return failure();
  literal = parser.getBuilder().getStringAttr(bytes);
  return success();
}

bool BigType::isLiteral(Attribute literal) const { return isa<BigAttr>(literal); }

ParseResult BigType::parseLiteral(AsmParser &parser, Attribute &literal) const {
  BigAttr big;
  if (parser.parseAttribute(big))
    return failure();
  literal = big;
  return success();
}

// A natural is never negative, which its type proves: the one place a
// natural's literal is said. It is written as a big's, and a negative one
// is no literal of it, which the op that holds it is refused for.
bool NatType::isLiteral(Attribute literal) const {
  auto big = dyn_cast<BigAttr>(literal);
  return big && !big.getValue().isNegative();
}

ParseResult NatType::parseLiteral(AsmParser &parser, Attribute &literal) const {
  return BigType::get(getContext()).parseLiteral(parser, literal);
}

void QType::getAsmName(OpAsmSetNameFn setNameFn) const {
  if (auto carrier = dyn_cast<OpAsmTypeInterface>(getValue()))
    carrier.getAsmName(setNameFn);
}

void WorldType::getAsmName(OpAsmSetNameFn setNameFn) const { setNameFn("w"); }
void StrType::getAsmName(OpAsmSetNameFn setNameFn) const { setNameFn("s"); }
void BigType::getAsmName(OpAsmSetNameFn setNameFn) const { setNameFn("n"); }
void NatType::getAsmName(OpAsmSetNameFn setNameFn) const { setNameFn("n"); }
void FnType::getAsmName(OpAsmSetNameFn setNameFn) const { setNameFn("f"); }
void LazyType::getAsmName(OpAsmSetNameFn setNameFn) const { setNameFn("lazy"); }
void idr::TokenType::getAsmName(OpAsmSetNameFn setNameFn) const { setNameFn("tok"); }
