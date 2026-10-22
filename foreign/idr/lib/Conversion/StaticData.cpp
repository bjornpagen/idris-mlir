// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The static data idr-lower-statics makes, each under the name of its
// content (StaticNames.cpp): a constant's datum and the data it holds, and
// the cells of a constructor, in place or in a cell; and the components of
// a constant, which the lowering and a static cell's fields both read. What
// holds no other datum is StaticBytes.cpp's.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Families/Families.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Symbols.h"
#include "idr/Conversion/StaticData.h"
#include "idr/Conversion/Words.h"
#include "idr/Support/Match.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinTypes.h"
#include "llvm/ADT/STLExtras.h"

#include <cassert>
#include <variant>

using namespace mlir;

namespace idr::conversion {

StaticData::StaticData(Operation *program, SymbolTable &symbols, const Layouts &layouts,
                       unsigned headerBytes)
    : program(program), symbols(symbols), layouts(layouts), headerBytes(headerBytes),
      at(program->getLoc()) {}

SmallVector<Value> StaticData::header(OpBuilder &b, layout::CellInfo info) {
  return {i32Constant(b, at, 0), i32Constant(b, at, info.word())};
}

// A struct of `members`, inserted one by one into the zero struct, which
// LLVM folds into one constant.
Value StaticData::pack(OpBuilder &b, Type structType, ValueRange members) {
  Value value = LLVM::ZeroOp::create(b, at, structType);
  for (auto [i, member] : llvm::enumerate(members))
    value = LLVM::InsertValueOp::create(b, at, value, member, static_cast<int64_t>(i));
  return value;
}

namespace {

// A constant at the type of the place that holds it (a constant op's
// result, or a field's slot). A constructor whose own type lays out apart
// from its place's, a closed one held in place where the place holds its
// member at an unknown index, is the same constructor at the place's type,
// so its datum and its words are the place's; a numeral is its value at
// any width, so it stays as it is.
Attribute atPlace(Attribute value, Type type) {
  auto con = dyn_cast<ConAttr>(value);
  auto place = dyn_cast<DataType>(unrestricted(type));
  if (!con || !place || families::isNumber(place.layout()) ||
      families::layoutMatch(con.getData(), place) == LayoutMatch::SameLayout)
    return value;
  return ConAttr::get(value.getContext(), place.refinedTo(con.getTag(), {}), con.getFields());
}

// Whether a constant is a numeral's value: a constructor of a family held
// as a number.
bool isNumeral(ConAttr con) { return families::isNumber(con.getData().layout()); }

} // namespace

// The ladder's one step of nesting is a constructor held in place, not in
// a cell, whose fields are its words, each at the type its slot is laid out
// at, which for a closed constant is its own unfolding; every other
// constant is one leaf. The constructors are listed in preorder, each
// before its fields and its first field next, and read back in reverse, so
// every field is made before what holds it and a constructor's fields lie
// on top of what is made, the first topmost: a constant nested to any depth
// takes none of the native stack.
SmallVector<Value> constantComponents(OpBuilder &b, Location loc, const Layouts &layouts,
                                      Attribute value, Type type) {
  auto inPlace = [](Attribute held) {
    auto con = dyn_cast<ConAttr>(held);
    return con && con.getData().layout() == Layout::InPlace ? con : ConAttr();
  };
  // A datum's address, or a scalar's constant. A numeral is its value at
  // its place's width, or as a natural where its place is one; an integer
  // or a Double is its own type's literal.
  auto leaf = [&](Attribute held, Type heldType) -> Value {
    if (auto text = dyn_cast<StringAttr>(held))
      return staticAddress(b, loc, StaticNames::string(text.getValue()));
    if (auto number = dyn_cast<BigAttr>(held))
      return bigConstant(b, loc, number);
    if (auto con = dyn_cast<ConAttr>(held); con && isNumeral(con)) {
      auto place = cast<DataType>(unrestricted(heldType));
      uint64_t value = families::numeralValue(con);
      if (place.layout() == Layout::Natural)
        return bigConstant(b, loc, BigAttr::get(b.getContext(), APInt(64, value)));
      Type word = layouts.components(place).front().type;
      return LLVM::ConstantOp::create(b, loc, word,
                                      IntegerAttr::get(word, static_cast<int64_t>(value)));
    }
    if (isa<IntegerAttr, FloatAttr>(held)) {
      auto literal = cast<TypedAttr>(held);
      return LLVM::ConstantOp::create(b, loc, literal.getType(), literal);
    }
    // Poison stands for a cell pointer only: of any other value it is each
    // component's (Cells.cpp).
    if (isa<ub::PoisonAttr>(held))
      return staticAddress(b, loc, StaticNames::nothing());
    return staticAddress(b, loc, StaticNames::cell(cast<ConAttr>(held), 0));
  };
  struct Held {
    Attribute value;
    Type type;
  };
  SmallVector<Held> order, left{{value, type}};
  while (!left.empty()) {
    Held held = left.pop_back_val();
    held.value = atPlace(held.value, held.type);
    order.push_back(held);
    if (ConAttr con = inPlace(held.value)) {
      // A field and its type are read at one position of two arrays alike.
      ArrayRef<Attribute> fields = con.getFields().getValue();
      ArrayRef<Type> types = layouts.fieldTypes(con.getData(), con.getTag());
      assert(fields.size() == types.size() && "a constructor's fields and their types pair up");
      for (size_t field = fields.size(); field-- > 0;)
        left.push_back({fields[field], types[field]});
    }
  }
  SmallVector<SmallVector<Value>> made;
  for (const Held &held : llvm::reverse(order)) {
    ConAttr con = inPlace(held.value);
    if (!con) {
      made.push_back({leaf(held.value, held.type)});
      continue;
    }
    SmallVector<SmallVector<Value>> fields;
    for (size_t field = 0, n = con.getFields().size(); field < n; ++field)
      fields.push_back(made.pop_back_val());
    SmallVector<ValueRange> words(fields.begin(), fields.end());
    made.push_back(unboxedSum(b, loc, layouts.sum(con.getData()), con.getTag(), words));
  }
  return made.pop_back_val();
}

// What a datum holds is pushed and made in turn, never by recursion, so a
// constant nested to any depth takes none of the native stack: a cell's
// initializer names the data its fields hold, which are made after it.
void StaticData::constant(Attribute value, Type type) {
  SmallVector<Held> left{{value, type}};
  auto make = [&](Held held) {
    held.value = atPlace(held.value, held.type);
    if (auto text = dyn_cast<StringAttr>(held.value))
      return string(text.getValue());
    if (auto number = dyn_cast<BigAttr>(held.value))
      return big(number);
    if (isa<ub::PoisonAttr>(held.value))
      return isCellPointer(held.type) ? nothing() : void();
    auto con = dyn_cast<ConAttr>(held.value);
    if (!con)
      return;
    // A numeral held as a natural past the small range is a big's datum.
    if (isNumeral(con)) {
      if (cast<DataType>(unrestricted(held.type)).layout() == Layout::Natural)
        big(BigAttr::get(at.getContext(), APInt(64, families::numeralValue(con))));
      return;
    }
    if (con.getData().layout() == Layout::Cell)
      return cells(con, left);
    // A sum held in place is its words, each field's datum made at the
    // type its slot is laid out at.
    for (auto [field, fieldType] :
         llvm::zip_equal(con.getFields(), layouts.fieldTypes(con.getData(), con.getTag())))
      left.push_back({field, fieldType});
  };
  while (!left.empty())
    make(left.pop_back_val());
}

// A constructor laid out in a cell as static data: its cells from the last
// of its spine run back to the first, each one before the last holding the
// address of the next at its spine, so the stack holds one cell however
// long the run. Cell `k` holds at position `i` the field fieldOfCell(k, i);
// a cell before the last holds no position for the spine field, which is
// the next cell's address. A run met before is made already, and so is what
// it holds: its first cell's name is the run's.
void StaticData::cells(ConAttr con, SmallVectorImpl<Held> &left) {
  if (symbols.lookup(StaticNames::cell(con, 0)))
    return;
  DataType data = con.getData();
  Tag tag = con.getTag();
  ArrayRef<Type> slots = layouts.fieldTypes(data, tag);
  unsigned runLength = con.getRunLength();
  const layout::Cell &cell = layouts.cells(data).cell(tag);
  // A memo cell, whose kind says a force writes it, is the one static cell
  // that is not constant. It is one per process: constant data holds its
  // address (a stream's tail), which a thread-local global's is not at link
  // time.
  Mutability mutability = data.memo() ? Mutability::Written : Mutability::Constant;
  // A packed struct with the padding as bytes of its own, so that LLVM puts
  // each word at the offset the layout chose, whatever data layout the
  // translation is given. After the header, each member is padding, a word
  // of the cell's own, or a component of a field, in address order: the own
  // words come before every slot, and `order` is the slots' address order.
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
  unsigned offset = headerBytes;
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
  Type i32 = IntegerType::get(ctx, 32);
  SmallVector<Type> types{i32, i32};
  for (const Member &member : members)
    types.push_back(member.type);
  auto structType = LLVM::LLVMStructType::getLiteral(ctx, types, /*isPacked=*/true);

  for (unsigned index = runLength; index-- > 0;) {
    // The fields this cell holds, each with its place in the constructor;
    // the data they hold are left to make.
    SmallVector<std::pair<unsigned, Attribute>> held;
    for (auto [position, value] : llvm::enumerate(con.getCell(index).getValue())) {
      unsigned field = con.fieldOfCell(index, static_cast<unsigned>(position));
      held.emplace_back(field, value);
      left.push_back({value, slots[field]});
    }
    global(StaticNames::cell(con, index), structType, mutability, headerBytes,
           [&](OpBuilder &init) -> Value {
             SmallVector<SmallVector<Value>> fields(slots.size());
             for (auto [field, value] : held)
               fields[field] = constantComponents(init, at, layouts, value, slots[field]);
             if (index + 1 < runLength)
               fields[con.getSpine()] = {
                   staticAddress(init, at, StaticNames::cell(con, index + 1))};
             SmallVector<Value> values = header(init, cell.info);
             for (const Member &member : members)
               values.push_back(idr::match(
                   member.is,
                   [&](Padding) -> Value { return LLVM::ZeroOp::create(init, at, member.type); },
                   [&](int64_t word) -> Value {
                     return LLVM::ConstantOp::create(init, at, member.type, word);
                   },
                   [&](Component slot) -> Value { return fields[slot.field][slot.component]; }));
             return pack(init, structType, values);
           });
  }
}

} // namespace idr::conversion
