// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The layouts of the values of a module, computed whole when a pass first
// asks for them. Every cell and element can be built: a count the header
// cannot hold, a tag beyond its field and an element too large for an
// array's header each have a representation, so no count refuses a
// program.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Symbols.h"
#include "idr/IR/TypeGraph.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Interfaces/DataLayoutInterfaces.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/Twine.h"
#include "llvm/Support/ErrorHandling.h"
#include "llvm/Support/MathExtras.h"

#include <cassert>

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

} // namespace

Layouts::Layouts(Operation *op) : root(op) {
  MLIRContext *ctx = op->getContext();
  DataLayout target = DataLayout::closest(op);
  auto record = [&](Type component) {
    if (!measures.contains(component))
      measures.try_emplace(component, measure(target, component));
  };
  // The runtime frees a cell by its object slots, which it reads as
  // pointers of the target it is compiled for, one word each, and the
  // program's verifier refuses a module whose target's pointers are not
  // those words (verify::program).
  Type pointer = LLVM::LLVMPointerType::get(ctx);
  assert(measure(target, pointer) ==
             std::make_pair(unsigned{IDRIS_RT_WORD_BYTES}, unsigned{IDRIS_RT_WORD_BYTES}) &&
         "a verified module's pointers are the runtime's words");
  // The scalars an element or a field may be, and every component a data
  // type holds, so that no query after this one needs the data layout's own
  // memory.
  for (Type scalar : {pointer, Type(IntegerType::get(ctx, 1)), Type(IntegerType::get(ctx, 8)),
                      Type(IntegerType::get(ctx, 16)), Type(IntegerType::get(ctx, 32)),
                      Type(IntegerType::get(ctx, 64)), Type(Float32Type::get(ctx)),
                      Type(Float64Type::get(ctx))})
    record(scalar);
  // Every data type a value or a body holds, with how it is held: the
  // sums held in place are slots, and the data types held in a box are
  // cells.
  TypeGraph graph(op);
  ArrayRef<DataType> types = graph.declarations();
  sums = layout::sumsOf(types);
  for (DataType data : types)
    for (const layout::Component &component : sum(data).words)
      record(component.type);
  for (DataType data : types)
    for (const Ctor &ctor : data.getCtors())
      for (Type field : ctor.fields)
        for (const layout::Component &component : components(field))
          record(component.type);

  for (DataType data : types) {
    if (!graph.boxed(data))
      continue;
    // A sum of more constructors than a header's tag holds keeps each
    // one's group in every cell. A memo cell is allocated in one state and
    // written into another, the value a force stores over the captures it
    // took, so every state's cell is as large as the largest, which is
    // known before the box's cells are stored.
    bool grouped = data.getCtors().size() > IDRIS_RT_TAG_LIMIT;
    bool memo = data.isMemo();
    layout::BoxLayout boxLayout;
    unsigned size = 0;
    for (Tag tag : data.getTags()) {
      boxLayout.cells.push_back(cellOf(data.getCtor(tag).fields, tag, grouped, memo));
      size = std::max(size, boxLayout.cells.back().size);
    }
    if (memo)
      for (layout::Cell &cell : boxLayout.cells)
        cell.size = size;
    // The group word is a grouped cell's last own word, at one offset in
    // every cell of the sum (cellOf).
    if (grouped)
      boxLayout.group = boxLayout.cells.front().words.back().offset;
    boxes.try_emplace(data, std::move(boxLayout));
  }
}

SmallVector<layout::Component> Layouts::components(Type type) const {
  return layout::components(type, sums);
}

const layout::SumLayout &Layouts::sum(DataType type) const {
  if (auto it = sums.find(type); it != sums.end())
    return *it->second;
  llvm::reportFatalInternalError("no layout of the sum \"" + type.getName() +
                                 "\", which no value of the module held when its layouts were "
                                 "computed");
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

// An element is laid out as a cell of one field, less the header: the
// offsets start at the element, and the stride is the element's size at
// its own alignment, so that a byte element takes one byte and a buffer's
// bytes are contiguous; an element with an object slot takes whole words.
// One whose size the array's header cannot hold, or whose object slots it
// cannot count, is held in a cell of its own, one counted pointer in the
// array.
layout::Element Layouts::element(Type type) const {
  // The cell of a box of one field, the one constructor of its sum.
  layout::Cell cell = cellOf(type, Tag{0}, /*grouped=*/false, /*memo=*/false);
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
  return layout::Element{{layout::Slot{{pointer, true}, 0}},
                         IDRIS_RT_WORD_BYTES,
                         layout::CellInfo::array(IDRIS_RT_WORD_BYTES, 1),
                         std::move(cell)};
}

// The header, then the cell's own words: the count word when the header
// cannot count the object slots (and in every cell of a sum with a group,
// so the group is where every cell of the sum has it), then the group. Then
// the object slots, each a word, so contiguous: the group, then the counted
// components. Then the other components.
layout::Cell Layouts::cellOf(ArrayRef<Type> fieldTypes, Tag tag, bool grouped,
                             bool memo) const {
  SmallVector<SmallVector<layout::Slot>> fields;
  unsigned objs = grouped ? 1u : 0u;
  for (Type field : fieldTypes) {
    SmallVector<layout::Slot> slots;
    for (const layout::Component &component : components(field)) {
      slots.push_back(layout::Slot{component, 0});
      objs += component.counted ? 1u : 0u;
    }
    fields.push_back(std::move(slots));
  }
  Type i64 = IntegerType::get(root->getContext(), 64);
  // Whether the header's objs field is IDRIS_RT_OBJS_WIDE, the word after
  // the header counting the object slots.
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
  // The counted components, the object slots, first; then the others, the
  // most aligned first, so that the small ones (the tags of unboxed sums,
  // characters, booleans) share a word instead of each taking one: the
  // order of fields in the source is not a layout.
  SmallVector<std::pair<unsigned, unsigned>> others;
  for (auto [f, slots] : llvm::enumerate(fields))
    for (auto [c, slot] : llvm::enumerate(slots)) {
      if (slot.counted)
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
  layout::CellInfo info =
      memo ? layout::CellInfo::thunk(tag, headerObjs) : layout::CellInfo::box(tag, headerObjs);
  return layout::Cell{std::move(fields),
                      static_cast<unsigned>(llvm::alignTo(at, IDRIS_RT_WORD_BYTES)),
                      objs,
                      std::move(order),
                      info,
                      std::move(words)};
}

const layout::BoxLayout &Layouts::box(DataType type) const {
  if (auto it = boxes.find(type); it != boxes.end())
    return it->second;
  llvm::reportFatalInternalError("no cells of \"" + type.getName() +
                                 "\", which no value of the module held in a box when its "
                                 "layouts were computed");
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
