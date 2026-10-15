// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The dialect's types: their generated definitions and their spellings,
// with the storage of a data type, which they need complete; the data
// type's body, set once and checked when it is; the canonical forms of
// !idr.q, the destination's carrier, and the names the printer gives a
// value of each type. A graded value takes its carrier's name, so a world
// is %w and a linear string %s.

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/DialectImplementation.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/TypeSwitch.h"

using namespace mlir;
using namespace idr;

//===----------------------------------------------------------------------===//
// The storage of a data type
//===----------------------------------------------------------------------===//

namespace idr::detail {

// A data type is identified by its name, the key, which holds no type, so
// upstream's walkers and replacers see the type as an atom. The body is the
// mutable part, set once as an LLVM identified struct's is
// (TypeDetail.h's mutate): a second setting succeeds only with the same
// body. The constructors and their fields live in the context's allocator,
// as the type does, and so does an index of the tags by name.
struct DataTypeStorage : TypeStorage {
  using KeyTy = StringRef;

  explicit DataTypeStorage(StringRef identifier) : name(identifier) {}

  bool operator==(const KeyTy &key) const { return key == name; }
  static llvm::hash_code hashKey(const KeyTy &key) { return llvm::hash_value(key); }
  static DataTypeStorage *construct(TypeStorageAllocator &allocator, const KeyTy &key) {
    return new (allocator.allocate<DataTypeStorage>()) DataTypeStorage(allocator.copyInto(key));
  }
  KeyTy getAsKey() const { return name; }

  LogicalResult mutate(TypeStorageAllocator &allocator, SumKind newKind, ArrayRef<Ctor> newCtors,
                       InstanceAttr newInstance) {
    if (initialized)
      return success(kind == newKind && instance == newInstance && ctors == newCtors);
    SmallVector<Ctor> copied;
    copied.reserve(newCtors.size());
    for (const Ctor &ctor : newCtors)
      copied.push_back({ctor.name, allocator.copyInto(ctor.fields), ctor.byName});
    ctors = allocator.copyInto(ArrayRef<Ctor>(copied));
    SmallVector<unsigned> order = llvm::to_vector(llvm::seq<unsigned>(0, static_cast<unsigned>(ctors.size())));
    llvm::sort(order, [&](unsigned a, unsigned b) {
      return ctors[a].name.getValue() < ctors[b].name.getValue();
    });
    byName = allocator.copyInto(ArrayRef<unsigned>(order));
    kind = newKind;
    instance = newInstance;
    initialized = true;
    return success();
  }

  StringRef name;
  bool initialized = false;
  SumKind kind = SumKind::Plain;
  ArrayRef<Ctor> ctors;
  InstanceAttr instance;
  // The tags, in the order of their constructors' names.
  ArrayRef<unsigned> byName;
};

} // namespace idr::detail

#define GET_TYPEDEF_CLASSES
#include "idr/IR/IdrTypes.cpp.inc"

void IdrDialect::registerTypes() {
  addTypes<
#define GET_TYPEDEF_LIST
#include "idr/IR/IdrTypes.cpp.inc"
      >();
}

//===----------------------------------------------------------------------===//
// Data types
//===----------------------------------------------------------------------===//

DataType DataType::get(MLIRContext *context, StringRef identifier) {
  return Base::get(context, identifier);
}

DataType DataType::getChecked(function_ref<InFlightDiagnostic()> emitError, MLIRContext *context,
                              StringRef identifier) {
  if (identifier.empty()) {
    emitError() << "expects a data type to have a name";
    return {};
  }
  return Base::get(context, identifier);
}

StringRef DataType::getName() const { return getImpl()->name; }
bool DataType::hasBody() const { return getImpl()->initialized; }
SumKind DataType::getKind() const { return getImpl()->kind; }
ArrayRef<Ctor> DataType::getCtors() const { return getImpl()->ctors; }
const Ctor &DataType::getCtor(unsigned tag) const { return getImpl()->ctors[tag]; }
InstanceAttr DataType::getInstance() const { return getImpl()->instance; }

std::optional<unsigned> DataType::getTag(StringRef ctor) const {
  ArrayRef<unsigned> order = getImpl()->byName;
  ArrayRef<Ctor> ctors = getImpl()->ctors;
  const unsigned *it = llvm::partition_point(
      order, [&](unsigned tag) { return ctors[tag].name.getValue() < ctor; });
  if (it == order.end() || ctors[*it].name.getValue() != ctor)
    return std::nullopt;
  return *it;
}

bool DataType::isLabel(unsigned tag) const {
  if (isClosures())
    return true;
  return isMemo() && tag < getRunningTag();
}

namespace {

// The rules of a well-formed sum, checked once, when its body is set: so a
// type with a body has them, and no op that meets one checks them again.
LogicalResult checkBody(DataType type, function_ref<InFlightDiagnostic()> emitError, SumKind kind,
                        ArrayRef<Ctor> ctors) {
  StringRef name = type.getName();
  llvm::SmallDenseSet<StringAttr, 8> names;
  for (const Ctor &ctor : ctors) {
    if (!ctor.name || ctor.name.getValue().empty())
      return emitError() << "the data type \"" << name << "\" has a constructor without a name";
    if (!names.insert(ctor.name).second)
      return emitError() << "the data type \"" << name << "\" has two constructors @"
                         << ctor.name.getValue();
    for (Type field : ctor.fields)
      if (!isFieldType(field))
        return emitError() << "the constructor @" << ctor.name.getValue() << " of \"" << name
                           << "\" has a field of unsupported type " << field;
  }
  if (kind == SumKind::Memo) {
    size_t n = ctors.size();
    if (n < 2 || ctors[n - 2].name.getValue() != memoRunning || !ctors[n - 2].fields.empty() ||
        ctors[n - 1].name.getValue() != memoForced || ctors[n - 1].fields.size() != 1)
      return emitError() << "the memo sum \"" << name << "\" ends in its states @" << memoRunning
                         << ", with no field, and @" << memoForced << ", with the value";
    // Only a label runs at a force, so only a label is by name.
    if (ctors[n - 2].byName || ctors[n - 1].byName)
      return emitError() << "the memo sum \"" << name
                         << "\" has a state by_name, which only a label is";
    return success();
  }
  for (const Ctor &ctor : ctors)
    if (ctor.byName)
      return emitError() << "the constructor @" << ctor.name.getValue() << " of \"" << name
                         << "\" is by_name, which only a label of a memo sum is";
  if (kind == SumKind::BaseList) {
    // The string ops walk and build base's list by its shape, which the
    // registry names and this states once.
    bool shaped = ctors.size() == 2 && ctors[DataType::listNil].fields.empty() &&
                  ctors[DataType::listCons].fields.size() == 2 &&
                  unrestricted(ctors[DataType::listCons].fields[1]) == BoxType::get(type);
    if (!shaped)
      return emitError() << "the list \"" << name
                         << "\" is a nil without fields, then a cons of an element and the list "
                            "in a box";
  }
  return success();
}

} // namespace

LogicalResult DataType::setBody(function_ref<InFlightDiagnostic()> emitError, SumKind kind,
                                ArrayRef<Ctor> ctors, InstanceAttr instance) {
  if (failed(checkBody(*this, emitError, kind, ctors)))
    return failure();
  if (failed(Base::mutate(kind, ctors, instance)))
    return emitError() << "the data type \"" << getName() << "\" has another body already";
  return success();
}

// `<"T">` inside the type's own body, `<"T", kind [@C(fields), ...]
// instance #idr.instance<...>>` everywhere else: the way LLVM writes an
// identified struct, which ends a cycle of types at its name.
void DataType::print(AsmPrinter &printer) const {
  FailureOr<AsmPrinter::CyclicPrintReset> cyclic = printer.tryStartCyclicPrint(*this);
  printer << '<';
  printer.printString(getName());
  if (failed(cyclic) || !hasBody()) {
    printer << '>';
    return;
  }
  printer << ", " << stringifySumKind(getKind()) << " [";
  llvm::interleaveComma(getCtors(), printer, [&](const Ctor &ctor) {
    printer.printSymbolName(ctor.name.getValue());
    printer << '(';
    llvm::interleaveComma(ctor.fields, printer);
    printer << ')';
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
  DataType type = getChecked([&] { return parser.emitError(nameLoc); }, context, identifier);
  if (!type)
    return {};
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
  SmallVector<StringAttr> names;
  SmallVector<SmallVector<Type>> fields;
  SmallVector<bool> byName;
  auto parseCtor = [&]() -> ParseResult {
    StringAttr ctorName;
    SmallVector<Type> ctorFields;
    if (parser.parseSymbolName(ctorName) ||
        parser.parseCommaSeparatedList(AsmParser::Delimiter::Paren, [&]() {
          return parser.parseType(ctorFields.emplace_back());
        }))
      return failure();
    names.push_back(ctorName);
    fields.push_back(std::move(ctorFields));
    byName.push_back(succeeded(parser.parseOptionalKeyword("by_name")));
    return success();
  };
  if (parser.parseCommaSeparatedList(AsmParser::Delimiter::Square, parseCtor))
    return {};
  InstanceAttr instance;
  if (succeeded(parser.parseOptionalKeyword("instance")) && parser.parseAttribute(instance))
    return {};
  if (parser.parseGreater())
    return {};
  SmallVector<Ctor> ctors;
  for (auto [ctorName, ctorFields, isByName] : llvm::zip_equal(names, fields, byName))
    ctors.push_back({ctorName, ctorFields, isByName});
  if (failed(type.setBody([&] { return parser.emitError(bodyLoc); }, *kind, ctors, instance)))
    return {};
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
