// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The layouts of the values of a module, computed whole when a pass first
// asks for them, from one walk of the module's value types and the fields
// of the data types they hold. Every cell and element can be built: a count
// the header cannot hold, a tag beyond its field and an element too large
// for an array's header each have a representation, so no count refuses a
// program.

#include "idr/IR/Families/Families.h"
#include "idr/IR/Families/Substitute.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/Support/Match.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/AttrTypeSubElements.h"
#include "mlir/Interfaces/DataLayoutInterfaces.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SetVector.h"
#include "llvm/ADT/Twine.h"
#include "llvm/Support/ErrorHandling.h"
#include "llvm/Support/MathExtras.h"

#include "idris_rt.h"

#include <algorithm>

using namespace mlir;

namespace idr {

namespace {

// The size and alignment of `component` as `target` lays it out.
std::pair<unsigned, unsigned> measure(const DataLayout &target, Type component) {
  return {static_cast<unsigned>(target.getTypeSize(component).getFixedValue()),
          static_cast<unsigned>(target.getTypeABIAlignment(component))};
}

// The data types a field of type `field` holds where it is: its own, or an
// array's elements'.
DataType heldData(Type field) {
  Type value = unrestricted(field);
  if (auto shaped = dyn_cast<ShapedType>(value))
    value = unrestricted(shaped.getElementType());
  return dyn_cast<DataType>(value);
}

// A closed application held in place: the one value of its member laid out
// over its own indices.
bool unfolded(DataType type) {
  return type.layout() == Layout::InPlace && type.cls() == Class::Closed;
}

} // namespace

// So a reindex between two applications of one member re-packs only where
// one is a closed application held in place, bounded by the shape budget.
families::TagSet Layouts::tagsLaidOut(DataType type) {
  if (unfolded(type))
    return type.unrefined().possibleTags();
  return families::TagSet::every(type.declaredCount());
}

// Unfolded, at the binders its indices determine, or at the constructor's
// own binders where they leave one open; any other value at the
// constructor's own binders. Either way a member of the group named by
// position is its data type, laid out as a value of that type is, by its
// class.
SmallVector<Type> Layouts::fieldsAt(DataType type, Tag tag) {
  if (unfolded(type))
    if (std::optional<SmallVector<Type>> fields = type.determinedFields(tag))
      return std::move(*fields);
  return families::instantiateFields(type.getGroup(), type.ctor(tag).fields, {});
}

// The components of each field of constructor `tag` at this application.
SmallVector<SmallVector<layout::Component>> Layouts::fieldsOf(DataType type, Tag tag) const {
  SmallVector<SmallVector<layout::Component>> out;
  for (Type field : fieldsAt(type, tag))
    out.push_back(components(field));
  return out;
}

Layouts::Layouts(Operation *op) : root(op) {
  MLIRContext *ctx = op->getContext();
  // The runtime frees a cell by its object slots, which it reads as
  // pointers of the target it is compiled for, one word each, and the
  // program's verifier refuses a module whose target's pointers are not
  // those words.
  Type pointer = LLVM::LLVMPointerType::get(ctx);
  for (Type scalar : {pointer, Type(IntegerType::get(ctx, 1)), Type(IntegerType::get(ctx, 8)),
                      Type(IntegerType::get(ctx, 16)), Type(IntegerType::get(ctx, 32)),
                      Type(IntegerType::get(ctx, 64)), Type(Float32Type::get(ctx)),
                      Type(Float64Type::get(ctx))})
    record(scalar);

  // Every data type a value of the module is of, a constant holds or an
  // attribute names, and every one their fields hold: the walk stays out of
  // a family's declaration, whose types are over its own binders.
  llvm::SetVector<DataType> found;
  AttrTypeWalker walker;
  walker.addWalk([](FamilyAttr) { return WalkResult::skip(); });
  walker.addWalk([&](DataType data) {
    found.insert(data);
    return WalkResult::advance();
  });
  op->walk([&](Operation *nested) {
    walker.walk(nested->getAttrDictionary());
    for (Type type : nested->getResultTypes())
      walker.walk(type);
    for (Region &region : nested->getRegions())
      for (Block &block : region)
        for (Type type : block.getArgumentTypes())
          walker.walk(type);
  });
  // Each type after the values in place its fields hold, whose slots its
  // own layout reads: the class rule keeps holding in place acyclic, so the
  // walk ends. A cell needs nothing of the cells its fields point to.
  auto heldBy = [](DataType type) {
    SmallVector<DataType> held;
    for (Tag tag : tagsLaidOut(type))
      for (Type field : fieldsAt(type, tag))
        if (DataType data = heldData(field))
          held.push_back(data.unrefined());
    return held;
  };
  // A number has neither slots nor cells: its value is its word. A frame
  // stack's frames are laid out as cells.
  auto computed = [&](DataType type) {
    return numbered.contains(type) ||
           (type.layout() != Layout::InPlace && type.layout() != Layout::Cell &&
            type.layout() != Layout::FrameStack);
  };
  for (size_t at = 0; at < found.size(); ++at) {
    SmallVector<std::pair<DataType, bool>> stack{{found[at].unrefined(), false}};
    while (!stack.empty()) {
      auto [type, expanded] = stack.pop_back_val();
      if (computed(type))
        continue;
      SmallVector<DataType> held = heldBy(type);
      if (!expanded) {
        stack.push_back({type, true});
        for (DataType data : held)
          if (data.layout() == Layout::InPlace && !computed(data))
            stack.push_back({data, false});
        continue;
      }
      for (DataType data : held)
        found.insert(data);
      // Its slots or cells are computed before it takes its number: a read
      // of another entry while they are copies what it reads, and nothing
      // moves once the layouts are made.
      std::variant<layout::SumLayout, layout::CellLayout> shape =
          type.layout() == Layout::InPlace
              ? std::variant<layout::SumLayout, layout::CellLayout>(sumOf(type))
              : std::variant<layout::SumLayout, layout::CellLayout>(cellsOf(type));
      layout::OwnCells own = ownCellsOf(type);
      numbered.try_emplace(type, static_cast<uint32_t>(laidOut.size()));
      laidOut.push_back(LaidOut{type, std::move(shape), std::move(own), std::nullopt});
    }
  }
  for (const LaidOut &entry : laidOut)
    match(
        entry.shape,
        [&](const layout::SumLayout &sum) {
          for (const layout::Component &component : sum.words)
            record(component.type);
        },
        [&](const layout::CellLayout &cells) {
          for (const layout::Cell &cell : cells.cells)
            for (const SmallVector<layout::Slot> &field : cell.fields)
              for (const layout::Slot &slot : field)
                record(slot.type);
        });
  computeReach();
}

void Layouts::record(Type component) {
  if (!measures.contains(component))
    measures.try_emplace(component, measure(DataLayout::closest(root), component));
}

// Essential: a pass may ask of a type the module did not hold when its
// layouts were computed, which is the compiler's error, not the program's.
const Layouts::LaidOut &Layouts::entryOf(DataType type, StringRef what) const {
  if (auto it = numbered.find(type.unrefined()); it != numbered.end())
    return laidOut[it->second];
  llvm::reportFatalInternalError(llvm::Twine("no ") + what +
                                 " of a data type that no value of the module held when its "
                                 "layouts were computed");
}

// A type's layout is one of the two, as its class says. Essential: asking
// a value in place for its cells, or a cell for its slots, is the asker's
// error, never the program's.
const layout::SumLayout &Layouts::sum(DataType type) const {
  return match(
      entryOf(type, "slots").shape,
      [](const layout::SumLayout &slots) -> const layout::SumLayout & { return slots; },
      [](const layout::CellLayout &) -> const layout::SumLayout & {
        llvm::reportFatalInternalError("the slots of a data type held in a cell");
      });
}

const layout::CellLayout &Layouts::cells(DataType type) const {
  return match(
      entryOf(type, "cells").shape,
      [](const layout::CellLayout &held) -> const layout::CellLayout & { return held; },
      [](const layout::SumLayout &) -> const layout::CellLayout & {
        llvm::reportFatalInternalError("the cells of a data type held in place");
      });
}

const layout::OwnCells &Layouts::ownCells(DataType type) const {
  return entryOf(type, "own cells").owned;
}

unsigned Layouts::sizeOf(Type component) const {
  if (auto it = measures.find(component); it != measures.end())
    return it->second.first;
  return measure(DataLayout::closest(root), component).first;
}

unsigned Layouts::alignmentOf(Type component) const {
  if (auto it = measures.find(component); it != measures.end())
    return it->second.second;
  return measure(DataLayout::closest(root), component).second;
}

// A sum of more constructors than a header's tag holds keeps each one's
// group in every cell. A memo cell is allocated in one state and written
// into another, the value a force stores over the captures it took, so
// every state's cell is as large as the largest.
layout::CellLayout Layouts::cellsOf(DataType type) const {
  bool grouped = type.declaredCount() > IDRIS_RT_TAG_LIMIT;
  layout::CellLayout out;
  unsigned size = 0;
  for (uint32_t t = 0, n = type.declaredCount(); t < n; ++t) {
    out.cells.push_back(cellOf(fieldsOf(type, Tag{t}), Tag{t}, grouped, type.kind()));
    size = std::max(size, out.cells.back().size);
  }
  if (type.kind() == MemberKind::Memo)
    for (layout::Cell &cell : out.cells)
      cell.size = size;
  if (grouped)
    out.group = out.cells.front().words.back().offset;
  return out;
}

// Each field a `unique self` claim reaches (fieldReach of its declared
// type), where its type at this application has cells or slots of its
// family, is walked as that type; a number's word, a frame stack and every
// field the claim does not reach are dropped by their counts.
layout::OwnCells Layouts::ownCellsOf(DataType type) const {
  layout::OwnCells out;
  for (uint32_t t = 0, n = type.declaredCount(); t < n; ++t) {
    SmallVector<layout::SelfDrop> &fields = out.fields.emplace_back();
    for (auto [declared, field] : llvm::zip_equal(type.ctor(Tag{t}).fields, fieldsAt(type, Tag{t}))) {
      if (fieldReach(declared) == FieldReach::Other) {
        fields.push_back(layout::ByCount{});
        continue;
      }
      // A field the claim reaches is of the value's own group, which its
      // type at the application makes a data type, or of an in_place
      // family: a data type either way.
      auto data = cast<DataType>(unrestricted(field));
      if (data.layout() == Layout::Cell || data.layout() == Layout::InPlace)
        fields.push_back(layout::OwnCell{data});
      else
        fields.push_back(layout::ByCount{});
    }
  }
  return out;
}

// An element is laid out as a cell of one field, less the header: the
// offsets start at the element, and the stride is the element's size at
// its own alignment, so that a byte element takes one byte and a buffer's
// bytes are contiguous; an element with an object slot takes whole words.
// One whose size the array's header cannot hold, or whose object slots it
// cannot count, is held in a cell of its own, one counted pointer in the
// array.
layout::Element Layouts::element(Type type) const {
  SmallVector<SmallVector<layout::Component>> one{components(type)};
  layout::Cell cell = cellOf(one, Tag{0}, /*grouped=*/false, MemberKind::Data);
  constexpr unsigned header = sizeof(idris_rt_header);
  SmallVector<layout::Slot> slots = cell.fields.front();
  unsigned end = 0, alignment = 1;
  for (layout::Slot &slot : slots) {
    slot.offset -= header;
    end = std::max(end, slot.offset + sizeOf(slot.type));
    alignment = std::max(alignment, alignmentOf(slot.type));
  }
  unsigned stride = static_cast<unsigned>(llvm::alignTo(end, alignment));
  if (cell.objs <= layout::mostObjects && stride < IDRIS_RT_TAG_LIMIT)
    return layout::Element{std::move(slots), stride, layout::CellInfo::array(stride, cell.objs),
                           std::nullopt};
  Type pointer = LLVM::LLVMPointerType::get(root->getContext());
  return layout::Element{{layout::Slot{{pointer, layout::Word::Cell}, 0}},
                         IDRIS_RT_WORD_BYTES,
                         layout::CellInfo::array(IDRIS_RT_WORD_BYTES, 1),
                         std::move(cell)};
}

// The header, then the cell's own words: the count word when the header
// cannot count the object slots (and in every cell of a sum with a group,
// so the group is where every cell of the sum has it), then the group. Then
// the object slots, each a word, so contiguous: the group, then the counted
// components. Then the other components, the most aligned first, so that
// the small ones share a word: the order of fields in the source is not a
// layout.
layout::Cell Layouts::cellOf(ArrayRef<SmallVector<layout::Component>> fieldComponents, Tag tag,
                             bool grouped, MemberKind kind) const {
  SmallVector<SmallVector<layout::Slot>> fields;
  unsigned objs = grouped ? 1u : 0u;
  for (const SmallVector<layout::Component> &field : fieldComponents) {
    SmallVector<layout::Slot> slots;
    for (const layout::Component &component : field) {
      slots.push_back(layout::Slot{component, 0});
      objs += component.counted() ? 1u : 0u;
    }
    fields.push_back(std::move(slots));
  }
  Type i64 = IntegerType::get(root->getContext(), 64);
  bool wide = grouped || objs > layout::mostObjects;
  unsigned at = sizeof(idris_rt_header);
  SmallVector<layout::OwnWord> words;
  if (wide) {
    words.push_back(layout::OwnWord{i64, at, static_cast<int64_t>(objs)});
    at += IDRIS_RT_WORD_BYTES;
  }
  if (grouped) {
    int64_t group = static_cast<int64_t>(static_cast<uint32_t>(tag) / IDRIS_RT_TAG_LIMIT);
    words.push_back(layout::OwnWord{i64, at, static_cast<int64_t>(idris_rt_small_word(group))});
    at += IDRIS_RT_WORD_BYTES;
  }
  SmallVector<std::pair<unsigned, unsigned>> order;
  auto place = [&](unsigned field, unsigned component) {
    layout::Slot &slot = fields[field][component];
    at = static_cast<unsigned>(llvm::alignTo(at, alignmentOf(slot.type)));
    slot.offset = at;
    at += sizeOf(slot.type);
    order.push_back({field, component});
  };
  SmallVector<std::pair<unsigned, unsigned>> others;
  for (auto [f, slots] : llvm::enumerate(fields))
    for (auto [c, slot] : llvm::enumerate(slots)) {
      if (slot.counted())
        place(static_cast<unsigned>(f), static_cast<unsigned>(c));
      else
        others.push_back({static_cast<unsigned>(f), static_cast<unsigned>(c)});
    }
  llvm::stable_sort(others, [&](std::pair<unsigned, unsigned> a, std::pair<unsigned, unsigned> b) {
    return alignmentOf(fields[a.first][a.second].type) > alignmentOf(fields[b.first][b.second].type);
  });
  for (auto [f, c] : others)
    place(f, c);
  std::optional<unsigned> headerObjs = wide ? std::nullopt : std::optional<unsigned>(objs);
  layout::CellInfo info = kind == MemberKind::Memo ? layout::CellInfo::thunk(tag, headerObjs)
                                                   : layout::CellInfo::constructor(tag, headerObjs);
  return layout::Cell{std::move(fields),
                      static_cast<unsigned>(llvm::alignTo(at, IDRIS_RT_WORD_BYTES)),
                      objs,
                      std::move(order),
                      info,
                      std::move(words)};
}

arith::CmpIPredicate layout::signedPredicate(CmpPredicate predicate) {
  switch (predicate) {
  case CmpPredicate::eq:
    return arith::CmpIPredicate::eq;
  case CmpPredicate::lt:
    return arith::CmpIPredicate::slt;
  case CmpPredicate::lte:
    return arith::CmpIPredicate::sle;
  case CmpPredicate::gt:
    return arith::CmpIPredicate::sgt;
  case CmpPredicate::gte:
    return arith::CmpIPredicate::sge;
  }
  llvm_unreachable("a comparison predicate");
}

} // namespace idr
