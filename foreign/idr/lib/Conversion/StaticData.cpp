// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The constants idr-lower writes as globals, each under the name of its
// content (StaticNames.cpp).

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Fold.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Symbols.h"
#include "idr/Conversion/Arrays.h"
#include "idr/Conversion/StaticData.h"
#include "idr/Conversion/Words.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/DialectResourceBlobManager.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/Support/raw_ostream.h"

#include <optional>
#include <variant>

// The runtime's C ABI: a string's and a big's static form is its cells',
// and the runtime itself reads a literal's text and says which words are
// small.
#include "idris_rt.h"

using namespace mlir;

namespace idr::conversion {

namespace {

// A static cell's header, the first two members of its struct, each an i32
// (idris_rt_header): the count, 0, the runtime's persistent mark, so
// nothing counts or frees the cell; and the info word.
SmallVector<Type> headerTypes(MLIRContext *ctx) {
  Type i32 = IntegerType::get(ctx, 32);
  return {i32, i32};
}

SmallVector<Value> header(OpBuilder &b, Location loc, layout::CellInfo info) {
  return {i32Constant(b, loc, 0), i32Constant(b, loc, info.word())};
}

// A digest as the words of a key.
std::string hex(Digest digest) {
  std::string text;
  llvm::raw_string_ostream(text) << digest;
  return text;
}

// What a datum that holds a global contributes to its holder's key: the
// global's name.
std::string referenceTo(LLVM::GlobalOp global) { return "&" + global.getSymName().str(); }

} // namespace

StaticData::StaticData(Location location, const Layouts &l)
    : at(location), layouts(l), scratch(ModuleOp::create(location)) {}

bool StaticData::isStatic(Value component) {
  Operation *def = component.getDefiningOp();
  return def && (isa<LLVM::AddressOfOp>(def) || def->hasTrait<OpTrait::ConstantLike>());
}

std::optional<LLVM::GlobalOp> StaticData::find(StringRef name) const {
  auto it = globals.find(name);
  if (it == globals.end())
    return std::nullopt;
  return it->second.global;
}

Value StaticData::message(OpBuilder &b, Location loc, StringRef text) {
  Named named = intern(loc, "msg", digestOf(text));
  auto type = LLVM::LLVMArrayType::get(b.getI8Type(), text.size());
  LLVM::GlobalOp message =
      global(named.name, named.key, type, /*isConstant=*/true, IDRIS_RT_WORD_BYTES,
             [&](OpBuilder &init) -> Value {
               return LLVM::ConstantOp::create(init, at, type, init.getStringAttr(text));
             });
  return LLVM::AddressOfOp::create(b, loc, message);
}

SmallVector<Value> StaticData::constant(OpBuilder &b, Location loc, Attribute value, Type type) {
  return datum(b, loc, value, type).components;
}

// The one ladder of constants: the world, strings, bigs, scalars, poison,
// then constructors, in place or in a box.
StaticData::Datum StaticData::datum(OpBuilder &b, Location loc, Attribute value, Type type) {
  // A linear value is the value itself at runtime; a world is nothing.
  if (isWorld(type))
    return {"world", {}};
  type = unrestricted(type);
  if (auto text = dyn_cast<StringAttr>(value)) {
    LLVM::GlobalOp bytes = string(loc, text.getValue());
    return {referenceTo(bytes), {LLVM::AddressOfOp::create(b, loc, bytes)}};
  }
  if (auto number = dyn_cast<BigAttr>(value)) {
    Digest key = canonicalHash(value);
    return {hex(key), {big(b, loc, number, key)}};
  }
  if (isa<IntegerAttr, FloatAttr>(value))
    return {hex(canonicalHash(value)),
            {LLVM::ConstantOp::create(b, loc, type, cast<TypedAttr>(value))}};
  // Poison stands for a cell pointer only: of any other value it is each
  // component's (Cells.cpp).
  if (isa<ub::PoisonAttr>(value)) {
    LLVM::GlobalOp cell = nothing(loc);
    return {referenceTo(cell), {LLVM::AddressOfOp::create(b, loc, cell)}};
  }
  auto con = cast<ConAttr>(value);
  if (isa<DataType>(type)) {
    // An unboxed sum held in place: one cell, its fields' components in its
    // slots.
    const Ctor &ctor = con.getCtor();
    SmallVector<std::string> keys;
    SmallVector<SmallVector<Value>> components;
    for (auto [i, field] : llvm::enumerate(con.getFields())) {
      Datum held = datum(b, loc, field, ctor.fields[i]);
      keys.push_back(std::move(held.key));
      components.push_back(std::move(held.components));
    }
    SmallVector<ValueRange> fields(components.begin(), components.end());
    return {hex(cellKey(type, ctor, keys)),
            unboxedSum(b, loc, layouts.sum(con.getData()), con.getTag(), fields)};
  }
  LLVM::GlobalOp cell = box(loc, con, type);
  return {referenceTo(cell), {LLVM::AddressOfOp::create(b, loc, cell)}};
}

FailureOr<ConstantArray> ConstantArray::of(memref::GlobalOp global) {
  std::optional<Attribute> initial = global.getInitialValue();
  auto elements = initial ? dyn_cast<ElementsAttr>(*initial) : ElementsAttr();
  if (!global.getConstant() || !elements || !holdsWords(global.getType())) {
    global.emitError() << "internal error: idr-lower: @" << global.getSymName()
                       << " is no constant array of words";
    return failure();
  }
  return ConstantArray(global.getType(), elements);
}

// A constant array is a cell like any other, its header in front of its
// data: count 0, the runtime's persistent mark, so nothing counts, frees or
// reads past the header; the info of an array of the element's bytes with
// no object slot; and the number of elements. Its data is at the cell's
// element 0, as every array's is, at a word's alignment, row-major: dense
// elements reshaped, a resource's blob as it is, any other form's elements
// written out. Its name is its value's and type's canonical digests, kept
// for each attribute, so a large constant is printed once.
Value StaticData::constantArray(OpBuilder &b, Location loc, const ConstantArray &array) {
  MemRefType type = array.type();
  ElementsAttr values = array.elements();
  std::string key;
  llvm::raw_string_ostream(key) << canonicalHash(Attribute(values)) << " : "
                                << canonicalHash(Type(type));
  Named named = intern(loc, "array", digestOf(key));
  Type element = type.getElementType();
  int64_t count = type.getNumElements();
  auto dataType = LLVM::LLVMArrayType::get(element, static_cast<unsigned>(count));
  layout::CellInfo info = layout::CellInfo::array(layouts.element(element).stride, 0);
  SmallVector<Type> members = headerTypes(b.getContext());
  members.append({b.getI64Type(), dataType});
  auto cellType = LLVM::LLVMStructType::getLiteral(b.getContext(), members);
  LLVM::GlobalOp cell =
      global(named.name, named.key, cellType, /*isConstant=*/true, IDRIS_RT_WORD_BYTES,
             [&](OpBuilder &init) -> Value {
               auto flatType = RankedTensorType::get({count}, element);
               Attribute flat;
               if (auto dense = dyn_cast<DenseElementsAttr>(values))
                 flat = dense.reshape(flatType);
               else if (auto resource = dyn_cast<DenseResourceElementsAttr>(values))
                 flat = DenseResourceElementsAttr::get(flatType, resource.getRawHandle());
               else
                 flat = DenseElementsAttr::get(flatType,
                                               llvm::to_vector(values.getValues<Attribute>()));
               SmallVector<Value> fields = header(init, at, info);
               fields.append({i64Constant(init, at, count),
                              LLVM::ConstantOp::create(init, at, dataType, flat)});
               return pack(init, at, cellType, fields);
             });
  return LLVM::AddressOfOp::create(b, loc, cell);
}

// A box as static data: its cells from the last back to the first, each
// one before the last holding the address of the next at its spine, so the
// stack holds one cell however long the run. Cell `k` holds at position `i`
// the field fieldOfCell(k, i); a cell before the last holds no position for
// the spine field, which is the next cell's address.
LLVM::GlobalOp StaticData::box(Location loc, ConAttr con, Type type) {
  if (auto it = boxes.find({con, type}); it != boxes.end())
    return it->second;
  DataType data = con.getData();
  const Ctor &ctor = con.getCtor();
  ArrayRef<ArrayAttr> cells = con.getCells();
  std::optional<LLVM::GlobalOp> next;
  for (size_t k = cells.size(); k-- > 0;) {
    auto cell = static_cast<unsigned>(k);
    // The first cell is the constant's; every other is a field's.
    Type cellType = k == 0 ? type : unrestricted(ctor.fields[con.getSpine()]);
    next = staticCell(loc, data, con.getTag(), cellType, [&](OpBuilder &init) {
      SmallVector<Datum> fields(ctor.fields.size());
      for (auto [position, value] : llvm::enumerate(cells[cell].getValue())) {
        unsigned field = con.fieldOfCell(cell, static_cast<unsigned>(position));
        fields[field] = datum(init, at, value, ctor.fields[field]);
      }
      if (next)
        fields[con.getSpine()] = {referenceTo(*next), {LLVM::AddressOfOp::create(init, at, *next)}};
      return fields;
    });
  }
  boxes.try_emplace({con, type}, *next);
  return *next;
}

// A box of the constructor `tag` as static data, count 0: its header, its
// own words, then the components of each field in the cell's address
// order. Its global is made before its name, which follows from its fields'
// keys, so each field is written once, by the walk that names it; a name
// another constant wrote already keeps that global, and this one goes. A
// memo cell, whose kind says a force writes it, is the one static cell that
// is not constant, and the release lists it. It is one per process:
// constant data holds its address (a stream's tail), which a thread-local
// global's is not at link time.
LLVM::GlobalOp StaticData::staticCell(Location loc, DataType data, Tag tag, Type type,
                                      function_ref<SmallVector<Datum>(OpBuilder &)> fields) {
  const layout::Cell &cell = layouts.box(data).cell(tag);
  bool memo = data.isMemo();
  // A packed struct with the padding as bytes of its own, so that LLVM puts
  // each word at the offset the layout chose, whatever data layout the
  // translation is given. After the header, each member is padding, a word
  // of the cell's own, or a component of a field, in address order: the
  // own words come before every slot, and `order` is the slots' address
  // order.
  MLIRContext *ctx = at.getContext();
  struct Padding {};
  struct Component {
    unsigned field, component;
  };
  struct Member {
    Type type;
    std::variant<Padding, int64_t, Component> is;
  };
  SmallVector<Member> members;
  unsigned offset = sizeof(idris_rt_header);
  auto place = [&](unsigned where, Member member) {
    if (where > offset)
      members.push_back(
          {LLVM::LLVMArrayType::get(IntegerType::get(ctx, 8), where - offset), Padding{}});
    offset = where + layouts.sizeOf(member.type);
    members.push_back(member);
  };
  for (const layout::OwnWord &word : cell.words)
    place(word.offset, {word.type, word.value});
  for (auto [field, component] : cell.order) {
    const layout::Slot &slot = cell.fields[field][component];
    place(slot.offset, {slot.type, Component{field, component}});
  }
  if (cell.size > offset)
    members.push_back(
        {LLVM::LLVMArrayType::get(IntegerType::get(ctx, 8), cell.size - offset), Padding{}});
  SmallVector<Type> types = headerTypes(ctx);
  for (const Member &member : members)
    types.push_back(member.type);
  auto structType = LLVM::LLVMStructType::getLiteral(ctx, types, /*isPacked=*/true);

  OpBuilder b = OpBuilder::atBlockEnd(scratch->getBody());
  auto made = LLVM::GlobalOp::create(b, at, structType, /*isConstant=*/!memo,
                                     LLVM::Linkage::Private, /*name=*/"", Attribute(),
                                     IDRIS_RT_WORD_BYTES);
  b.createBlock(&made.getInitializerRegion());
  SmallVector<Datum> given = fields(b);
  SmallVector<Value> values = header(b, at, cell.info);
  for (const Member &member : members)
    values.push_back(std::visit(
        llvm::makeVisitor(
            [&](Padding) -> Value { return LLVM::ZeroOp::create(b, at, member.type); },
            [&](int64_t word) -> Value {
              return LLVM::ConstantOp::create(b, at, member.type, word);
            },
            [&](Component slot) -> Value {
              return given[slot.field].components[slot.component];
            }),
        member.is));
  LLVM::ReturnOp::create(b, at, pack(b, at, structType, values));

  SmallVector<std::string> keys =
      llvm::map_to_vector(given, [](const Datum &field) { return field.key; });
  Named named = intern(loc, kindOf(data), cellKey(type, data.getCtor(tag), keys));
  if (std::optional<LLVM::GlobalOp> written = find(named.name)) {
    made.erase();
    return *written;
  }
  made.setSymName(named.name);
  globals[named.name] = Written{made, named.key};
  if (memo)
    cafs.insert(named.name);
  return made;
}

LLVM::GlobalOp StaticData::global(StringRef name, Digest key, Type type, bool isConstant,
                                  unsigned alignment, function_ref<Value(OpBuilder &)> init) {
  if (std::optional<LLVM::GlobalOp> written = find(name))
    return *written;
  OpBuilder b = OpBuilder::atBlockEnd(scratch->getBody());
  Location loc = at;
  auto written = LLVM::GlobalOp::create(b, loc, type, isConstant, LLVM::Linkage::Private, name,
                                        Attribute(), alignment);
  b.createBlock(&written.getInitializerRegion());
  LLVM::ReturnOp::create(b, loc, init(b));
  globals[name] = Written{written, key};
  return written;
}

// A struct of `members`, inserted one by one into the zero struct, which
// LLVM folds into one constant.
Value StaticData::pack(OpBuilder &b, Location loc, Type structType, ValueRange members) {
  Value value = LLVM::ZeroOp::create(b, loc, structType);
  for (auto [i, member] : llvm::enumerate(members))
    value = LLVM::InsertValueOp::create(b, loc, value, member, static_cast<int64_t>(i));
  return value;
}

// A string: the header (count 0: static data), the byte length and the
// scalar count, which the runtime computes, then the bytes.
LLVM::GlobalOp StaticData::string(Location loc, StringRef bytes) {
  Named named = intern(loc, "str", digestOf(bytes));
  MLIRContext *ctx = at.getContext();
  Type i64 = IntegerType::get(ctx, 64);
  SmallVector<Type> members = headerTypes(ctx);
  members.append({i64, i64});
  if (!bytes.empty())
    members.push_back(LLVM::LLVMArrayType::get(IntegerType::get(ctx, 8), bytes.size()));
  auto type = LLVM::LLVMStructType::getLiteral(ctx, members);
  auto scalars = static_cast<int64_t>(idris_rt_utf8_count(bytes.data(), bytes.size()));
  // Whether the string is ASCII is its two counts' agreement, which the
  // runtime reads; the header says nothing of it.
  auto write = [&](OpBuilder &init) -> Value {
    SmallVector<Value> values = header(init, at, layout::CellInfo::string());
    values.append({i64Constant(init, at, static_cast<int64_t>(bytes.size())),
                   i64Constant(init, at, scalars)});
    if (!bytes.empty())
      values.push_back(
          LLVM::ConstantOp::create(init, at, members.back(), init.getStringAttr(bytes)));
    return pack(init, at, type, values);
  };
  return global(named.name, named.key, type, /*isConstant=*/true, IDRIS_RT_WORD_BYTES, write);
}

// A big: the runtime reads the decimal text (one semantics for what a
// big literal denotes); a small result is its tagged word, any other a
// static idris_rt_bignum, its limbs in the same global, named from the
// literal. The folders' scope holds what the runtime gives and releases it
// when this returns, counted as theirs are; the limbs are read before then.
Value StaticData::big(OpBuilder &b, Location loc, BigAttr value, Digest key) {
  fold::Scope scope(b.getContext());
  idris_rt_big word = scope.big(value);
  if (idris_rt_word_is_small(word))
    return i64Constant(b, loc, word);
  Named named = intern(loc, "big", key);
  const auto *number = reinterpret_cast<const idris_rt_bignum *>(word);
  int64_t size = number->size;
  auto count = static_cast<size_t>(size < 0 ? -size : size);
  SmallVector<int64_t> limbs;
  const auto *digitsOf = reinterpret_cast<const uint64_t *>(number + 1);
  for (size_t i = 0; i < count; ++i)
    limbs.push_back(static_cast<int64_t>(digitsOf[i]));
  auto i64 = b.getI64Type();
  auto limbsType = LLVM::LLVMArrayType::get(i64, count);
  SmallVector<Type> members = headerTypes(b.getContext());
  members.append({i64, limbsType});
  auto type = LLVM::LLVMStructType::getLiteral(b.getContext(), members);
  LLVM::GlobalOp digits = global(named.name, named.key, type, /*isConstant=*/true,
                                 IDRIS_RT_WORD_BYTES,
                                 [&](OpBuilder &init) -> Value {
    Value limbsValue = LLVM::ConstantOp::create(
        init, at, limbsType,
        DenseElementsAttr::get(
            RankedTensorType::get({static_cast<int64_t>(count)}, init.getI64Type()),
            ArrayRef<int64_t>(limbs)));
    SmallVector<Value> values = header(init, at, layout::CellInfo::bignum());
    values.append({i64Constant(init, at, size), limbsValue});
    return pack(init, at, type, values);
  });
  Value address = LLVM::AddressOfOp::create(b, loc, digits);
  return LLVM::PtrToIntOp::create(b, loc, b.getI64Type(), address);
}

// The null object of a cell pointer: one static cell, a box's header with
// no object slot and nothing after it, count 0, so counting it changes
// nothing, and a cell, so every fact of a cell pointer holds of it. Poison
// is never read, so no field of it is.
LLVM::GlobalOp StaticData::nothing(Location loc) {
  Named named = intern(loc, "nothing", digestOf("nothing"));
  auto type = LLVM::LLVMStructType::getLiteral(at.getContext(), headerTypes(at.getContext()));
  return global(named.name, named.key, type, /*isConstant=*/true, IDRIS_RT_WORD_BYTES,
                [&](OpBuilder &init) -> Value {
                  return pack(init, at, type, header(init, at, layout::CellInfo::box(Tag{0}, 0)));
                });
}

} // namespace idr::conversion
