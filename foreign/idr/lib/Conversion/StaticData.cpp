// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The static data idr-lower's serial phase makes, and the table of the
// globals made (Statics): a constant's datum and the data it holds, and
// the cells of a constructor, in place or in a cell; and the components of
// a constant, which the lowering and a static cell's fields both read off
// the table. What holds no other datum is StaticBytes.cpp's.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Symbols.h"
#include "idr/Conversion/StaticData.h"
#include "idr/Conversion/Words.h"
#include "idr/Support/Match.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinTypes.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/Support/ErrorHandling.h"

#include <cassert>
#include <string>
#include <variant>

using namespace mlir;

namespace idr::conversion {

namespace {

// Every reference the lowering writes names a datum the making met, so one
// it did not is the making's internal error.
[[noreturn]] void unmade() {
  llvm::reportFatalInternalError(
      "idr-lower names a static datum that its making of static data did not make");
}

// The global made for `key`.
template <typename Map, typename Key>
typename Map::mapped_type madeFor(const Map &made, const Key &key) {
  auto found = made.find(key);
  if (found == made.end())
    unmade();
  return found->second;
}


} // namespace

FlatSymbolRefAttr Statics::string(StringAttr value) const { return madeFor(strings, value); }
FlatSymbolRefAttr Statics::big(BigAttr value) const { return madeFor(bigs, value); }
FlatSymbolRefAttr Statics::natural(uint64_t value) const { return madeFor(naturals, value); }
FlatSymbolRefAttr Statics::cell(ConAttr con) const { return madeFor(cells, con); }
FlatSymbolRefAttr Statics::array(StringAttr global) const { return madeFor(arrays, global); }
SiteTexts Statics::site(SiteAttr site) const { return madeFor(sites, site); }
FlatSymbolRefAttr Statics::account(StringAttr function) const {
  return madeFor(accounts, function);
}
FlatSymbolRefAttr Statics::nothing() const { return nothingCell; }
// The homes' cursors are made only where the program opens a home, which a
// home's put or opener names.
FlatSymbolRefAttr Statics::homes() const {
  if (!homeCursors)
    unmade();
  return homeCursors;
}

Value staticAddress(OpBuilder &b, Location loc, FlatSymbolRefAttr global) {
  return LLVM::AddressOfOp::create(b, loc, ptrType(b.getContext()), global);
}

StaticData::StaticData(Operation *program, const Layouts &layouts, unsigned headerBytes)
    : program(program), layouts(layouts), headerBytes(headerBytes), at(program->getLoc()) {
  nothing();
}

FlatSymbolRefAttr StaticData::name(StringRef kind) {
  return FlatSymbolRefAttr::get(at.getContext(), reservedName(kind, std::to_string(named++)));
}

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

// Every form but a constructor in place, which holds forms of its own: one
// leaf each.
template <class T>
concept LeafForm = OneOf<T, static_form::Text, static_form::Big, static_form::Numeral,
                         static_form::Word, static_form::Nothing, static_form::Cell>;

// The word of a big of value `value`: a small one's own word, or the
// address of the static bignum `datum` names, as a word.
template <std::invocable<> Datum>
Value bigWord(OpBuilder &b, Location loc, const APInt &value, Datum &&datum) {
  if (std::optional<int64_t> word = smallWordOf(value))
    return i64Constant(b, loc, *word);
  return LLVM::PtrToIntOp::create(b, loc, b.getI64Type(), staticAddress(b, loc, datum()));
}

} // namespace

// The one step of nesting is a constructor held in place, not in a cell,
// whose fields are its words, each at the type its slot is laid out
// at, which for a closed constant is its own unfolding; every other
// constant is one leaf. The constructors are listed in preorder, each
// before its fields and its first field next, and read back in reverse, so
// every field is made before what holds it and a constructor's fields lie
// on top of what is made, the first topmost: a constant nested to any depth
// takes none of the native stack.
SmallVector<Value> constantComponents(OpBuilder &b, Location loc, const Layouts &layouts,
                                      const Statics &statics, Attribute value, Type type) {
  struct Held {
    Attribute value;
    Type type;
  };
  // Each constant's form at its place.
  SmallVector<StaticForm> order;
  SmallVector<Held> left{{value, type}};
  while (!left.empty()) {
    Held held = left.pop_back_val();
    order.push_back(staticFormOf(held.value, held.type));
    match(
        order.back(),
        [&](const static_form::InPlace &in) {
          // A field and its type are read at one position of two arrays
          // alike.
          ConAttr con = in.con.get();
          ArrayRef<Attribute> fields = con.getFields().getValue();
          ArrayRef<Type> types = layouts.fieldTypes(con.getData(), con.getTag());
          assert(fields.size() == types.size() && "a constructor's fields and their types pair up");
          for (size_t field = fields.size(); field-- > 0;)
            left.push_back({fields[field], types[field]});
        },
        [](const LeafForm auto &) {});
  }
  // A datum's address, or a scalar's constant. A numeral is its value at
  // its place's width, or as a natural where its place is one; an integer
  // or a Double is its own type's literal.
  SmallVector<SmallVector<Value>> made;
  for (const StaticForm &form : llvm::reverse(order)) {
    SmallVector<Value> components = match(
        form,
        [&](const static_form::InPlace &in) -> SmallVector<Value> {
          ConAttr con = in.con.get();
          SmallVector<SmallVector<Value>> fields;
          for (size_t field = 0, n = con.getFields().size(); field < n; ++field)
            fields.push_back(made.pop_back_val());
          SmallVector<ValueRange> words(fields.begin(), fields.end());
          return unboxedSum(b, loc, layouts.sum(con.getData()), con.getTag(), words);
        },
        [&](const static_form::Text &text) -> SmallVector<Value> {
          return {staticAddress(b, loc, statics.string(text.value))};
        },
        [&](const static_form::Big &big) -> SmallVector<Value> {
          BigAttr number = big.value.get();
          return {bigWord(b, loc, number.getValue(), [&] { return statics.big(number); })};
        },
        [&](const static_form::Numeral &numeral) -> SmallVector<Value> {
          DataType place = numeral.place.get();
          if (place.layout() == Layout::Natural)
            return {bigWord(b, loc, naturalValue(numeral.value),
                            [&] { return statics.natural(numeral.value); })};
          Type word = layouts.components(place).front().type;
          return {LLVM::ConstantOp::create(
              b, loc, word, IntegerAttr::get(word, static_cast<int64_t>(numeral.value)))};
        },
        [&](const static_form::Word &word) -> SmallVector<Value> {
          return {LLVM::ConstantOp::create(b, loc, word.literal.getType(), word.literal)};
        },
        // Poison stands for a cell pointer only: of any other value it is
        // each component's (Cells.cpp).
        [&](static_form::Nothing) -> SmallVector<Value> {
          return {staticAddress(b, loc, statics.nothing())};
        },
        [&](const static_form::Cell &cell) -> SmallVector<Value> {
          return {staticAddress(b, loc, statics.cell(cell.con.get()))};
        });
    made.push_back(std::move(components));
  }
  return made.pop_back_val();
}

// What a datum holds is pushed and met in turn, never by recursion, so a
// constant nested to any depth takes none of the native stack.
void StaticData::constant(Attribute value, Type type) {
  SmallVector<Held> left{{value, type}};
  auto meet = [&](Held held) {
    match(
        staticFormOf(held.value, held.type),
        [&](const static_form::Text &text) { string(text.value); },
        [&](const static_form::Big &number) { big(number.value.get()); },
        // A numeral held as a natural is a big; at a word's width it is
        // its value, no datum.
        [&](const static_form::Numeral &numeral) {
          if (numeral.place.get().layout() == Layout::Natural)
            natural(numeral.value);
        },
        // An integer or a Double is its own type's literal, no datum.
        [](const static_form::Word &) {},
        // `nothing` is made before any constant is met.
        [](static_form::Nothing) {},
        [&](const static_form::Cell &cell) { run(cell.con.get(), left); },
        // A sum held in place is its words, each field's datum met at the
        // type its slot is laid out at.
        [&](const static_form::InPlace &in) {
          ConAttr con = in.con.get();
          for (auto [field, fieldType] :
               llvm::zip_equal(con.getFields(), layouts.fieldTypes(con.getData(), con.getTag())))
            left.push_back({field, fieldType});
        });
  };
  while (!left.empty())
    meet(left.pop_back_val());
}

// A constructor laid out in a cell as static data: a run of cells along
// its spine, each named now, and what each holds left to meet; the cells
// are made by `made`, when every datum their fields hold is named. A run
// met before is named already, and so is what it holds.
void StaticData::run(ConAttr con, SmallVectorImpl<Held> &left) {
  if (table.cells.contains(con))
    return;
  // A memo cell, whose kind says a force writes it, is named apart.
  StringRef kind = con.getData().memo() ? "caf" : "cell";
  Run spine{con, {}};
  ArrayRef<Type> slots = layouts.fieldTypes(con.getData(), con.getTag());
  for (unsigned index = 0, n = con.getRunLength(); index < n; ++index) {
    spine.cells.push_back(name(kind));
    for (auto [position, value] : llvm::enumerate(con.getCell(index).getValue()))
      left.push_back({value, slots[con.fieldOfCell(index, static_cast<unsigned>(position))]});
  }
  table.cells.try_emplace(con, spine.cells.front());
  runs.push_back(std::move(spine));
}

// The cells of a run, each one before the last holding the address of the
// next at its spine. Cell `k` holds at position `i` the field
// fieldOfCell(k, i); a cell before the last holds no position for the spine
// field, which is the next cell's address.
void StaticData::cells(const Run &run) {
  ConAttr con = run.con;
  DataType data = con.getData();
  Tag tag = con.getTag();
  ArrayRef<Type> slots = layouts.fieldTypes(data, tag);
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

  for (unsigned index = 0, n = static_cast<unsigned>(run.cells.size()); index < n; ++index) {
    global(run.cells[index], structType, mutability, headerBytes, [&](OpBuilder &init) -> Value {
      SmallVector<SmallVector<Value>> fields(slots.size());
      for (auto [position, value] : llvm::enumerate(con.getCell(index).getValue())) {
        unsigned field = con.fieldOfCell(index, static_cast<unsigned>(position));
        fields[field] = constantComponents(init, at, layouts, table, value, slots[field]);
      }
      if (index + 1 < n)
        fields[con.getSpine()] = {staticAddress(init, at, run.cells[index + 1])};
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

Statics StaticData::made() && {
  for (const Run &run : runs)
    cells(run);
  return std::move(table);
}

} // namespace idr::conversion
