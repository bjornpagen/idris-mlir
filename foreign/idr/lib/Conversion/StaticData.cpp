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

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/DialectResourceBlobManager.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/Support/raw_ostream.h"

#include <optional>
#include <variant>

// The runtime's C ABI: a string's and a big's static form is its cells',
// the runtime itself reads a literal's text, and a cell's kind is its info
// word's, as the runtime reads it.
#include "idris_rt.h"

using namespace mlir;

namespace idr::conversion {

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
               return LLVM::ConstantOp::create(init, at, type,
                                               init.getStringAttr(text));
             });
  return LLVM::AddressOfOp::create(b, loc, message);
}

SmallVector<Value> StaticData::constant(OpBuilder &b, Location loc, Attribute value, Type type) {
  // A linear value is the value itself at runtime; a world is nothing.
  if (isWorld(type))
    return {};
  type = unrestricted(type);
  if (auto text = dyn_cast<StringAttr>(value))
    return {string(b, loc, text.getValue())};
  if (auto number = dyn_cast<BigAttr>(value))
    return {big(b, loc, number)};
  if (isa<IntegerAttr, FloatAttr>(value))
    return {LLVM::ConstantOp::create(b, loc, type, cast<TypedAttr>(value))};
  auto con = cast<ConAttr>(value);
  if (isa<DataType>(type))
    return unboxed(b, loc, con);
  return {LLVM::AddressOfOp::create(b, loc, box(loc, con, type))};
}

FailureOr<ConstantArray> ConstantArray::of(memref::GlobalOp global) {
  std::optional<Attribute> initial = global.getInitialValue();
  auto elements = initial ? dyn_cast<ElementsAttr>(*initial) : ElementsAttr();
  if (!global.getConstant() || !elements || !holdsWords(global.getType())) {
    global.emitError() << "internal error: idr-lower: @" << global.getSymName()
                       << " is no constant array of words";
    return failure();
  }
  if (std::optional<uint64_t> alignment = global.getAlignment();
      alignment && *alignment > IDRIS_RT_WORD_BYTES) {
    global.emitError() << "internal error: idr-lower: @" << global.getSymName()
                       << " is aligned to " << *alignment << " bytes, past a cell's element";
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
  uint32_t info = layout::CellInfo::array(layouts.element(element).stride, 0).word();
  auto i32 = b.getI32Type(), i64 = b.getI64Type();
  auto cellType = LLVM::LLVMStructType::getLiteral(b.getContext(), {i32, i32, i64, dataType});
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
               return pack(init, at, cellType,
                           {i32Constant(init, at, 0), i32Constant(init, at, info),
                            i64Constant(init, at, count),
                            LLVM::ConstantOp::create(init, at, dataType, flat)});
             });
  return LLVM::AddressOfOp::create(b, loc, cell);
}

// An unboxed sum of constant fields.
SmallVector<Value> StaticData::unboxed(OpBuilder &b, Location loc, ConAttr con) {
  const Ctor &ctor = con.getCtor();
  SmallVector<SmallVector<Value>> components;
  for (auto [i, field] : llvm::enumerate(con.getFields()))
    components.push_back(constant(b, loc, field, ctor.fields[i]));
  SmallVector<ValueRange> fields(components.begin(), components.end());
  return unboxedSum(b, loc, layouts.sum(con.getData()), con.getTag(), fields);
}

// The global of the box `con` of type `type`, written once however many
// constants hold it.
LLVM::GlobalOp StaticData::box(Location loc, ConAttr con, Type type) {
  if (con.isRun())
    return run(loc, con, type);
  Named named = boxName(loc, con, type);
  if (std::optional<LLVM::GlobalOp> written = find(named.name))
    return *written;
  Tag tag = con.getTag();
  const Ctor &ctor = con.getCtor();
  ArrayAttr fields = con.getFields();
  return staticCell(named, layouts.box(con.getData(), tag), tag, [&](OpBuilder &init, unsigned i) {
    return constant(init, at, fields[i], ctor.fields[i]);
  });
}

// The cells of a run, written from its tail back to its first cell, each
// pointing at the one written before it: however long the list, the stack
// holds one cell. A cell already written under its name is the one a
// constant that names the run from there wrote.
LLVM::GlobalOp StaticData::run(Location loc, ConAttr con, Type type) {
  DataType data = con.getData();
  Tag tag = con.getTag();
  const Ctor &ctor = con.getCtor();
  unsigned spine = con.getSpine();
  Type spineType = unrestricted(ctor.fields[spine]);
  ArrayRef<ArrayAttr> cells = con.getRunCells();
  LLVM::GlobalOp rest = box(loc, cast<ConAttr>(con.getTail()), spineType);
  SmallVector<Named> named = runNames(loc, con, type);
  boxNames.try_emplace({con, type}, named.front());
  for (size_t k = cells.size(); k-- > 0;) {
    if (std::optional<LLVM::GlobalOp> written = find(named[k].name)) {
      rest = *written;
      continue;
    }
    rest = staticCell(named[k], layouts.box(data, tag), tag,
                      [&](OpBuilder &init, unsigned i) -> SmallVector<Value> {
                        if (i == spine)
                          return {LLVM::AddressOfOp::create(init, at, rest)};
                        // A run's cell holds its fields without the spine.
                        return constant(init, at, cells[k][i < spine ? i : i - 1],
                                        ctor.fields[i]);
                      });
  }
  return rest;
}

// Whether a force writes a cell of this layout: a memo cell, by its kind.
bool StaticData::isMemoCell(const layout::Cell &cell) {
  return idris_rt_info_kind(cell.info.word()) == IDRIS_RT_KIND_THUNK;
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

// A box of the constructor `tag` as static data, count 0: its header, the
// count of its object slots when the header cannot hold it, its group when
// its sum has more constructors than a header's tag holds, then the
// components of each field in the cell's address order. A memo cell, whose
// kind says a force writes it, is the one static cell that is not
// constant, and the release lists it. It is one per process: constant data
// holds its address (a stream's tail), which a thread-local global's is not
// at link time.
LLVM::GlobalOp StaticData::staticCell(
    const Named &named, const layout::Cell &cell, Tag tag,
    function_ref<SmallVector<Value>(OpBuilder &, unsigned field)> components) {
  bool memo = isMemoCell(cell);
  // A packed struct with the padding as bytes of its own, so that LLVM puts
  // each word at the offset the layout chose, whatever data layout the
  // translation is given. Each member is padding, a word of the cell's
  // own, or a component of a field.
  MLIRContext *ctx = at.getContext();
  auto i32 = IntegerType::get(ctx, 32), i64 = IntegerType::get(ctx, 64);
  struct Padding {};
  struct OwnWord {
    int64_t value;
  };
  struct Component {
    unsigned field, component;
  };
  struct Member {
    Type type;
    std::variant<Padding, OwnWord, Component> is;
  };
  SmallVector<Member> members{{i32, OwnWord{0}}, {i32, OwnWord{cell.info.word()}}};
  unsigned offset = sizeof(idris_rt_header);
  auto padTo = [&](unsigned next) {
    if (next > offset)
      members.push_back(
          {LLVM::LLVMArrayType::get(IntegerType::get(ctx, 8), next - offset), Padding{}});
    offset = next;
  };
  if (cell.countWord()) {
    members.push_back({i64, OwnWord{static_cast<int64_t>(cell.objs)}});
    offset += layouts.sizeOf(i64);
  }
  // The group word, and each component, in address order.
  SmallVector<std::pair<unsigned, Member>> placed;
  if (cell.group)
    placed.push_back(
        {cell.group->offset,
         {cell.group->type, OwnWord{groupWord(tag)}}});
  for (auto [field, component] : cell.order) {
    const layout::Slot &slot = cell.fields[field][component];
    placed.push_back({slot.offset, {slot.type, Component{field, component}}});
  }
  llvm::stable_sort(placed, [](const auto &a, const auto &b) { return a.first < b.first; });
  for (auto &[slotOffset, member] : placed) {
    padTo(slotOffset);
    members.push_back(member);
    offset += layouts.sizeOf(member.type);
  }
  padTo(cell.size);
  auto structType = LLVM::LLVMStructType::getLiteral(
      ctx, llvm::map_to_vector(members, [](const Member &m) { return m.type; }),
      /*isPacked=*/true);
  LLVM::GlobalOp cellGlobal = global(named.name, named.key, structType, /*isConstant=*/!memo,
                                     IDRIS_RT_WORD_BYTES, [&](OpBuilder &init) -> Value {
    SmallVector<SmallVector<Value>> fields;
    for (unsigned field = 0; field < cell.fields.size(); ++field)
      fields.push_back(components(init, field));
    SmallVector<Value> values;
    for (const Member &member : members)
      values.push_back(std::visit(
          llvm::makeVisitor(
              [&](Padding) -> Value { return LLVM::ZeroOp::create(init, at, member.type); },
              [&](OwnWord word) -> Value {
                return LLVM::ConstantOp::create(init, at, member.type, word.value);
              },
              [&](Component place) -> Value { return fields[place.field][place.component]; }),
          member.is));
    return pack(init, at, structType, values);
  });
  if (memo)
    cafs.insert(named.name);
  return cellGlobal;
}

// A string: the header (count 0: static data), the byte length and the
// scalar count, which the runtime computes, then the bytes.
Value StaticData::string(OpBuilder &b, Location loc, StringRef bytes) {
  Named named = intern(loc, "str", digestOf(bytes));
  auto i32 = b.getI32Type(), i64 = b.getI64Type();
  SmallVector<Type> members{i32, i32, i64, i64};
  if (!bytes.empty())
    members.push_back(LLVM::LLVMArrayType::get(b.getI8Type(), bytes.size()));
  auto type = LLVM::LLVMStructType::getLiteral(b.getContext(), members);
  auto scalars = static_cast<int64_t>(idris_rt_utf8_count(bytes.data(), bytes.size()));
  // Whether the string is ASCII is its two counts' agreement, which the
  // runtime reads; the header says nothing of it.
  uint32_t info = layout::CellInfo::string().word();
  auto write = [&](OpBuilder &init) -> Value {
    SmallVector<Value> values{i32Constant(init, at, 0), i32Constant(init, at, info),
                              i64Constant(init, at, static_cast<int64_t>(bytes.size())),
                              i64Constant(init, at, scalars)};
    if (!bytes.empty())
      values.push_back(
          LLVM::ConstantOp::create(init, at, members.back(), init.getStringAttr(bytes)));
    return pack(init, at, type, values);
  };
  LLVM::GlobalOp text =
      global(named.name, named.key, type, /*isConstant=*/true, IDRIS_RT_WORD_BYTES, write);
  return LLVM::AddressOfOp::create(b, loc, text);
}

// A big: the runtime reads the decimal text (one semantics for what a
// big literal denotes); a small result is its tagged word, any other a
// static idris_rt_bignum, its limbs in the same global, named from the
// literal. The folders' scope holds what the runtime gives and releases it
// when this returns, counted as theirs are; the limbs are read before then.
Value StaticData::big(OpBuilder &b, Location loc, BigAttr value) {
  fold::Scope scope(b.getContext());
  idris_rt_big word = scope.big(value);
  if ((word & 1) != 0)
    return i64Constant(b, loc, word);
  Named named = intern(loc, "big", canonicalHash(Attribute(value)));
  const auto *number = reinterpret_cast<const idris_rt_bignum *>(word);
  int64_t size = number->size;
  auto count = static_cast<size_t>(size < 0 ? -size : size);
  SmallVector<int64_t> limbs;
  const auto *digitsOf = reinterpret_cast<const uint64_t *>(number + 1);
  for (size_t i = 0; i < count; ++i)
    limbs.push_back(static_cast<int64_t>(digitsOf[i]));
  auto i32 = b.getI32Type();
  auto i64 = b.getI64Type();
  auto limbsType = LLVM::LLVMArrayType::get(i64, count);
  auto type = LLVM::LLVMStructType::getLiteral(b.getContext(), {i32, i32, i64, limbsType});
  LLVM::GlobalOp digits = global(named.name, named.key, type, /*isConstant=*/true,
                                 IDRIS_RT_WORD_BYTES,
                                 [&](OpBuilder &init) -> Value {
    Value limbsValue = LLVM::ConstantOp::create(
        init, at, limbsType,
        DenseElementsAttr::get(
            RankedTensorType::get({static_cast<int64_t>(count)}, init.getI64Type()),
            ArrayRef<int64_t>(limbs)));
    return pack(init, at, type,
                {i32Constant(init, at, 0), i32Constant(init, at, layout::CellInfo::bignum().word()),
                 i64Constant(init, at, size), limbsValue});
  });
  Value address = LLVM::AddressOfOp::create(b, loc, digits);
  return LLVM::PtrToIntOp::create(b, loc, b.getI64Type(), address);
}

} // namespace idr::conversion
