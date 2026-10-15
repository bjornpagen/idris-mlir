// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The constants idr-lower writes as globals, each under the name of its
// content (StaticNames.cpp).

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Fold.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Symbols.h"
#include "idr/Conversion/StaticData.h"
#include "idr/Conversion/Words.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinTypes.h"

// The runtime's C ABI: a string's and a big's static form is its cells',
// the runtime itself reads a literal's text, and a cell's kind is its info
// word's, as the runtime reads it.
#include "idris_rt.h"

using namespace mlir;

namespace idr::conversion {

StaticData::StaticData(ModuleOp m, const Layouts &l)
    : module(m), layouts(l), scratch(ModuleOp::create(m.getLoc())) {}

bool StaticData::isStatic(Value component) {
  Operation *def = component.getDefiningOp();
  return def && (isa<LLVM::AddressOfOp>(def) || def->hasTrait<OpTrait::ConstantLike>());
}

LLVM::GlobalOp StaticData::find(StringRef name) const {
  auto it = globals.find(name);
  return it == globals.end() ? LLVM::GlobalOp() : it->second.global;
}

Value StaticData::message(OpBuilder &b, Location loc, StringRef text) {
  Named named = intern(loc, "msg", text.str());
  auto type = LLVM::LLVMArrayType::get(b.getI8Type(), text.size());
  LLVM::GlobalOp message =
      global(named.name, named.key, type, /*isConstant=*/true, IDRIS_RT_WORD_BYTES,
             [&](OpBuilder &init) -> Value {
               return LLVM::ConstantOp::create(init, module.getLoc(), type,
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
  if (auto data = dyn_cast<DataType>(type))
    return unboxed(b, loc, con, data);
  return {LLVM::AddressOfOp::create(b, loc, box(loc, con, type))};
}

// A constant array is a cell like any other, its header in front of its
// data: count 0, the runtime's persistent mark, so nothing counts, frees or
// reads past the header; the info of an array of the element's bytes with
// no object slot; and the number of elements. Its data is at the cell's
// element 0, as every array's is, at a word's alignment.
Value StaticData::constantArray(OpBuilder &b, Location loc, memref::GlobalOp array) {
  MemRefType type = array.getType();
  auto values = cast<DenseElementsAttr>(*array.getInitialValue());
  Named named = intern(loc, "array", printed(values) + " : " + printed(Type(type)));
  Type element = type.getElementType();
  int64_t count = type.getNumElements();
  auto dataType = LLVM::LLVMArrayType::get(element, static_cast<unsigned>(count));
  auto flat = values.reshape(RankedTensorType::get({count}, element));
  unsigned stride = layouts.element(element)->stride;
  uint32_t info = layout::CellInfo::array(stride, 0)->word();
  auto i32 = b.getI32Type(), i64 = b.getI64Type();
  auto cellType = LLVM::LLVMStructType::getLiteral(b.getContext(), {i32, i32, i64, dataType});
  LLVM::GlobalOp cell =
      global(named.name, named.key, cellType, /*isConstant=*/true, IDRIS_RT_WORD_BYTES,
             [&](OpBuilder &init) -> Value {
               Location at = module.getLoc();
               return pack(init, at, cellType,
                           {i32Constant(init, at, 0), i32Constant(init, at, info),
                            i64Constant(init, at, count),
                            LLVM::ConstantOp::create(init, at, dataType, flat)});
             });
  return LLVM::AddressOfOp::create(b, loc, cell);
}

// An unboxed sum: its tag, then its slots.
SmallVector<Value> StaticData::unboxed(OpBuilder &b, Location loc, ConAttr con, DataType data) {
  const layout::SumLayout &layout = layouts.sum(data);
  unsigned tag = *data.getTag(con.getCtor().getValue());
  const Ctor &ctor = data.getCtor(tag);
  SmallVector<Value> slots(layout.slots.size());
  for (auto [i, field] : llvm::enumerate(con.getFields()))
    for (auto [slot, component] :
         llvm::zip_equal(layout.fields[tag][i], constant(b, loc, field, ctor.fields[i])))
      slots[slot] = component;
  SmallVector<Value> out;
  if (layout.tag)
    out.push_back(LLVM::ConstantOp::create(b, loc, layout.tag, static_cast<int64_t>(tag)));
  // A slot the constructor does not use holds zero: empty where the slot
  // is counted, so that counting the sum counts each of its slots.
  for (auto [slot, component] : llvm::enumerate(slots))
    out.push_back(component ? component
                            : LLVM::ZeroOp::create(b, loc, layout.slots[slot]).getResult());
  return out;
}

// The global of the box `con` of type `type`, written once however many
// constants hold it.
LLVM::GlobalOp StaticData::box(Location loc, ConAttr con, Type type) {
  if (con.isRun())
    return run(loc, con, type);
  Named named = boxName(loc, con, type);
  if (LLVM::GlobalOp written = find(named.name))
    return written;
  DataType data = dataTypeOf(type);
  unsigned tag = *data.getTag(con.getCtor().getValue());
  const Ctor &ctor = data.getCtor(tag);
  ArrayAttr fields = con.getFields();
  return staticCell(named, layouts.box(data, tag), [&](OpBuilder &init, unsigned i) {
    return constant(init, module.getLoc(), fields[i], ctor.fields[i]);
  });
}

// The cells of a run, written from its tail back to its first cell, each
// pointing at the one written before it: however long the list, the stack
// holds one cell. A cell already written under its name is the one a
// constant that names the run from there wrote.
LLVM::GlobalOp StaticData::run(Location loc, ConAttr con, Type type) {
  DataType data = dataTypeOf(type);
  unsigned tag = *data.getTag(con.getCtor().getValue());
  const Ctor &ctor = data.getCtor(tag);
  unsigned spine = con.getSpine();
  Type spineType = unrestricted(ctor.fields[spine]);
  ArrayRef<ArrayAttr> cells = con.getRunCells();
  LLVM::GlobalOp rest = box(loc, cast<ConAttr>(con.getTail()), spineType);
  SmallVector<Named> named = runNames(loc, con, type);
  boxNames.try_emplace({con, type}, named.front());
  for (size_t k = cells.size(); k-- > 0;) {
    if (LLVM::GlobalOp written = find(named[k].name)) {
      rest = written;
      continue;
    }
    rest = staticCell(named[k], layouts.box(data, tag),
                      [&](OpBuilder &init, unsigned i) -> SmallVector<Value> {
                        if (i == spine)
                          return {LLVM::AddressOfOp::create(init, module.getLoc(), rest)};
                        // A run's cell holds its fields without the spine.
                        return constant(init, module.getLoc(), cells[k][i < spine ? i : i - 1],
                                        ctor.fields[i]);
                      });
  }
  return rest;
}

// Whether a force writes a cell of this layout: a memo cell, by its kind.
bool StaticData::isMemoCell(const layout::Cell &cell) {
  return idris_rt_info_kind(cell.info.word()) == IDRIS_RT_KIND_THUNK;
}

LLVM::GlobalOp StaticData::global(StringRef name, StringRef key, Type type, bool isConstant,
                                  unsigned alignment, function_ref<Value(OpBuilder &)> init) {
  if (LLVM::GlobalOp written = find(name))
    return written;
  OpBuilder b = OpBuilder::atBlockEnd(scratch->getBody());
  Location loc = module.getLoc();
  auto written = LLVM::GlobalOp::create(b, loc, type, isConstant, LLVM::Linkage::Private, name,
                                        Attribute(), alignment);
  b.createBlock(&written.getInitializerRegion());
  LLVM::ReturnOp::create(b, loc, init(b));
  globals[name] = Written{written, key.str()};
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

// A box of `ctor` as static data, count 0: its header, then the
// components of each field in the cell's address order. A memo cell, whose
// kind says a force writes it, is the one static cell that is not
// constant, and the release lists it. It is one per process: constant
// data holds its address (a stream's tail), which a thread-local global's
// is not at link time.
LLVM::GlobalOp StaticData::staticCell(
    const Named &named, const layout::Cell &cell,
    function_ref<SmallVector<Value>(OpBuilder &, unsigned field)> components) {
  bool memo = isMemoCell(cell);
  // A packed struct with the padding as bytes of its own, so that LLVM puts
  // each component at the offset the layout chose, whatever data layout the
  // translation is given.
  MLIRContext *ctx = module.getContext();
  auto i32 = IntegerType::get(ctx, 32);
  SmallVector<Type> members{i32, i32};
  // For each member, the component it holds, or none for padding.
  SmallVector<std::optional<std::pair<unsigned, unsigned>>> holds{std::nullopt, std::nullopt};
  unsigned at = sizeof(idris_rt_header);
  auto padTo = [&](unsigned offset) {
    if (offset > at) {
      members.push_back(LLVM::LLVMArrayType::get(IntegerType::get(ctx, 8), offset - at));
      holds.push_back(std::nullopt);
    }
    at = offset;
  };
  for (auto [field, component] : cell.order) {
    const layout::Slot &slot = cell.fields[field][component];
    padTo(slot.offset);
    members.push_back(slot.type);
    holds.push_back(std::make_pair(field, component));
    at += layouts.sizeOf(slot.type);
  }
  padTo(cell.size);
  auto structType = LLVM::LLVMStructType::getLiteral(ctx, members, /*isPacked=*/true);
  LLVM::GlobalOp cellGlobal = global(named.name, named.key, structType, /*isConstant=*/!memo,
                                     IDRIS_RT_WORD_BYTES, [&](OpBuilder &init) -> Value {
    Location loc = module.getLoc();
    SmallVector<SmallVector<Value>> fields;
    for (unsigned field = 0; field < cell.fields.size(); ++field)
      fields.push_back(components(init, field));
    SmallVector<Value> values{i32Constant(init, loc, 0), i32Constant(init, loc, cell.info.word())};
    for (auto [type, held] : llvm::drop_begin(llvm::zip_equal(members, holds), 2))
      values.push_back(held ? fields[held->first][held->second]
                            : LLVM::ZeroOp::create(init, loc, type).getResult());
    return pack(init, loc, structType, values);
  });
  if (memo)
    cafs.insert(named.name);
  return cellGlobal;
}

// A string: the header (count 0: static data), the byte length and the
// scalar count, which the runtime computes, then the bytes.
Value StaticData::string(OpBuilder &b, Location loc, StringRef bytes) {
  Named named = intern(loc, "str", bytes.str());
  auto i32 = b.getI32Type(), i64 = b.getI64Type();
  SmallVector<Type> members{i32, i32, i64, i64};
  if (!bytes.empty())
    members.push_back(LLVM::LLVMArrayType::get(b.getI8Type(), bytes.size()));
  auto type = LLVM::LLVMStructType::getLiteral(b.getContext(), members);
  bool ascii = idris_rt_ascii(bytes.data(), bytes.size());
  auto scalars = static_cast<int64_t>(idris_rt_utf8_count(bytes.data(), bytes.size()));
  uint32_t info = layout::CellInfo::string(ascii).word();
  auto write = [&](OpBuilder &init) -> Value {
    Location at = module.getLoc();
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
  Named named = intern(loc, "big", printed(Attribute(value)));
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
    Location at = module.getLoc();
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
