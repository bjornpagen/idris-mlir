// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The dialect's types: their generated definitions and their spellings,
// with the storage of a data type, which they need complete, and what
// touches it: the body, made with the type, and the facts of what its
// values hold, kept beside it under the context's lock; the canonical forms
// of !idr.q, the destination's carrier, and the names the printer gives a
// value of each type. A graded value takes its carrier's name, so a world
// is %w and a linear string %s. How a body is checked and written is
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
      copied.push_back(
          {ctor.name, allocator.copyInto(ctor.fields), ctor.byName, ctor.role, ctor.fn});
    ctors = allocator.copyInto(ArrayRef<Ctor>(copied));
    SmallVector<Tag> order = llvm::to_vector(llvm::map_range(
        llvm::seq<uint32_t>(0, static_cast<uint32_t>(ctors.size())),
        [](uint32_t tag) { return Tag{tag}; }));
    llvm::sort(order, [&](Tag a, Tag b) { return name(a) < name(b); });
    byName = allocator.copyInto(ArrayRef<Tag>(order));
    for (auto [tag, ctor] : llvm::enumerate(ctors))
      roleTags[static_cast<size_t>(ctor.role)] = Tag{static_cast<uint32_t>(tag)};
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
  assert(tag && getCtor(*tag).role == role && "a role the data type has one constructor of");
  return *tag;
}

void DataType::walkLabels(DataType type, function_ref<void(Attribute)> walk) {
  for (const Ctor &ctor : type.getCtors())
    if (ctor.fn)
      walk(ctor.fn);
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
    if (!ctor.fn)
      continue;
    if (rest.empty() || rest.front() != ctor.fn)
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

FailureOr<DataType> DataType::define(MLIRContext *context, StringRef identifier,
                                     function_ref<Body(DataType self)> body) {
  auto emitError = [&] {
    return mlir::emitError(UnknownLoc::get(context)) << "internal error: ";
  };
  if (identifier.empty())
    return emitError() << "a data type has no name";
  DataType type = get(context, identifier);
  if (failed(type.setBody(emitError, body(type))))
    return failure();
  return type;
}

//===----------------------------------------------------------------------===//
// The dialect's spellings of its types
//===----------------------------------------------------------------------===//

namespace {

// The world, written whole: a !idr.q of the world's carrier, which is only
// ever at (one, plain).
bool isGradedWorld(Type type) { return isa<QType>(type) && isWorld(type); }

// The dialect's spellings of a value at a grade, read and written from this
// one table: a whole type, or a grade over any value. Any other grade is
// the generated `!idr.q<quantity, permission, value>`, as is every grade
// when written out; the world's carrier alone is `!idr.world_carrier`. The
// wholes come first: the world is (one, plain) too.
struct Whole {
  StringRef keyword;
  Type (*make)(MLIRContext *);
  bool (*is)(Type);
};
constexpr Whole wholes[] = {{"world", idr::world, isGradedWorld}};

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
  for (const Whole &whole : wholes)
    if (succeeded(parser.parseOptionalKeyword(whole.keyword)))
      return whole.make(ctx);
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
  for (const Whole &whole : wholes)
    if (whole.is(type)) {
      printer << whole.keyword;
      return;
    }
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
// Grades and destinations
//===----------------------------------------------------------------------===//

// The canonical forms: a plain type is (many, plain) and is never written
// as a grade; a grade is of a carrier, never of a grade; the world is at
// (one, plain) only, and so is a tensor, an array value, whose one grade is
// the quantity Idris proved of it; any other grade is of a runtime type.
LogicalResult QType::verify(function_ref<InFlightDiagnostic()> emitError, Quantity quantity,
                            Permission permission, Type value) {
  Grade grade{quantity, permission};
  if (grade.plain())
    return emitError() << "expects a grade other than (many, plain), which is the plain type";
  if (isa<QType>(value))
    return emitError() << "expects a grade of a plain type, got one of " << value;
  if (isa<WorldType, RankedTensorType>(value)) {
    if (grade != Grade{Quantity::One, Permission::Plain})
      return emitError() << "expects " << value << " at (one, plain)";
    if (isa<RankedTensorType>(value) && !isFieldType(value))
      return emitError() << "expects a grade of a runtime type, got " << value;
    return success();
  }
  // A runtime type: one a field may have, or a token, which is owned.
  if (!isFieldType(value) && !isa<TokenType>(value))
    return emitError() << "expects a grade of a runtime type, got " << value;
  return success();
}

// A destination is one word of a cell that a box's reference fills: a
// field of box type.
LogicalResult DestType::verify(function_ref<InFlightDiagnostic()> emitError, Type value) {
  if (!isa<BoxType>(value))
    return emitError() << "expects !idr.dest of a box type, got " << value;
  return success();
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
