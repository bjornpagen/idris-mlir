// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The static data idr-lower-statics makes, each under the name of its
// content (StaticNames.cpp): a constant's datum and the data it holds, and
// the cells of a constructor, in place or in a cell. What holds no other
// datum is StaticBytes.cpp's.

#include "idr/IR/IdrDialect.h"
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

// The one ladder of constants a field may hold: strings, bigs, scalars,
// then constructors, held in place or in a cell. A constant whose value is
// a datum is that datum's address, the datum made first.
SmallVector<Value> StaticData::components(OpBuilder &b, Attribute value, Type type) {
  type = unrestricted(type);
  if (auto text = dyn_cast<StringAttr>(value)) {
    string(text.getValue());
    return {staticAddress(b, at, StaticNames::string(text.getValue()))};
  }
  if (auto number = dyn_cast<BigAttr>(value)) {
    big(number);
    return {bigConstant(b, at, number)};
  }
  if (isa<IntegerAttr, FloatAttr>(value))
    return {LLVM::ConstantOp::create(b, at, type, cast<TypedAttr>(value))};
  auto con = cast<ConAttr>(value);
  DataType data = con.getData();
  if (data.layout() == Layout::Cell) {
    cells(con);
    return {staticAddress(b, at, StaticNames::cell(con, 0))};
  }
  // A sum held in place: its fields' components in its words.
  families::CtorView ctor = data.ctor(con.getTag());
  SmallVector<SmallVector<Value>> held;
  for (auto [field, fieldType] : llvm::zip_equal(con.getFields(), ctor.fields))
    held.push_back(components(b, field, fieldType));
  SmallVector<ValueRange> fields(held.begin(), held.end());
  return unboxedSum(b, at, layouts.sum(data), con.getTag(), fields);
}

void StaticData::constant(Attribute value, Type type) {
  if (auto text = dyn_cast<StringAttr>(value))
    return string(text.getValue());
  if (auto number = dyn_cast<BigAttr>(value))
    return big(number);
  if (isa<ub::PoisonAttr>(value))
    return isCellPointer(type) ? nothing() : void();
  auto con = dyn_cast<ConAttr>(value);
  if (!con)
    return;
  if (con.getData().layout() == Layout::Cell)
    return cells(con);
  // A sum held in place is its words, each field's datum made.
  families::CtorView ctor = con.getData().ctor(con.getTag());
  for (auto [field, fieldType] : llvm::zip_equal(con.getFields(), ctor.fields))
    constant(field, fieldType);
}

// A constructor laid out in a cell as static data: its cells from the last
// of its spine run back to the first, each one before the last holding the
// address of the next at its spine, so the stack holds one cell however
// long the run. Cell `k` holds at position `i` the field fieldOfCell(k, i);
// a cell before the last holds no position for the spine field, which is
// the next cell's address. A run met before is made already: its first
// cell's name is the run's.
void StaticData::cells(ConAttr con) {
  if (symbols.lookup(StaticNames::cell(con, 0)))
    return;
  DataType data = con.getData();
  Tag tag = con.getTag();
  families::CtorView ctor = data.ctor(tag);
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
    global(StaticNames::cell(con, index), structType, mutability, headerBytes,
           [&](OpBuilder &init) -> Value {
             SmallVector<SmallVector<Value>> fields(ctor.fields.size());
             for (auto [position, value] : llvm::enumerate(con.getCell(index).getValue())) {
               unsigned field = con.fieldOfCell(index, static_cast<unsigned>(position));
               fields[field] = components(init, value, ctor.fields[field]);
             }
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
