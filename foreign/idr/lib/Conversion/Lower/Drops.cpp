// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A drop. A value its type claims `unique self` has its own cells unshared:
// its family's cells and, through every field of an in_place family, theirs,
// and the storage of every buffer they hold, though not that buffer's
// elements. Its drop frees each of them with no count read, and drops every
// field the claim says nothing of by its counts. Any other value loses one
// reference to each counted word, a cell freed at 0.
//
// The walk runs in steps, each freeing one cell (the value's first, or
// reading its words in place) and leaving the own cells it holds: the first
// is the next step's and the rest wait on the thread's frame stack, so a
// structure of any depth and branching is freed by one loop, with no native
// stack and nothing taken from the heap. A step reads a constructor only
// where its type leaves more than one possible; an atom of a family in
// cells is the static cell of its constructor, which nothing frees. A value
// whose own cells end within it takes the first step alone.

#include "idr/Conversion/Lower/Lower.h"

#include "idr/IR/Grades.h"
#include "idr/Conversion/Words.h"
#include "idr/Support/Match.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/Sequence.h"
#include "llvm/ADT/SmallVectorExtras.h"
#include "llvm/Support/MathExtras.h"

#include <iterator>
#include <variant>

using namespace mlir;

namespace idr::conversion {

namespace {

// Where a dying value whose own cells the claim covers is: a cell of its
// own, freed once its fields are read, or its words in place.
struct InCell {
  Value cell;
};
struct InWords {
  SmallVector<Value> words;
};
using Where = std::variant<InCell, InWords>;

// A part of a dying value a step has still to drop: components dropped by
// their counts; an own cell left to the walk's loop, with the state that
// frees it; a value whose constructor is still to be read; one whose
// constructor is known.
struct ByCountPart {
  SmallVector<layout::Component> components;
  SmallVector<Value> values;
};
struct LaterPart {
  Value cell;
  int64_t state;
};
struct UnreadPart {
  DataType data;
  Where where;
};
struct ReadPart {
  DataType data;
  Where where;
  Tag tag;
};
using Part = std::variant<ByCountPart, LaterPart, UnreadPart, ReadPart>;

// The cells a walk may meet past the value it starts from: every data type
// held in a cell that an own field reaches, through the values in place its
// own fields hold, numbered from 1 as the states of the walk's loop; state 0
// takes the newest cell left on the frame stack. Each is a type the layouts
// hold, so the set is finite, and each is read once.
class Walk {
public:
  Walk(const Layouts &layouts, DataType from) {
    SmallVector<DataType> unread{from};
    DenseSet<DataType> spread;
    while (!unread.empty()) {
      DataType data = unread.pop_back_val();
      for (Tag tag : data.possibleTags())
        for (const layout::SelfDrop &drop : layouts.ownCells(data).of(tag))
          idr::match(
              drop,
              // A field dropped by its counts, and a buffer's storage, freed
              // where its holder's fields are read, are no cell the loop
              // frees, so they give it no state.
              [](const OneOf<layout::FreeStorage, layout::ReleaseStorage,
                             layout::ByCount> auto &) {},
              [&](const layout::OwnCell &own) {
                // An own field is a cell, which the loop frees, or in place,
                // part of whatever holds it.
                if (own.data.layout() == Layout::Cell) {
                  if (states.try_emplace(own.data, static_cast<int64_t>(order.size()) + 1)
                          .second) {
                    order.push_back(own.data);
                    unread.push_back(own.data);
                  }
                } else if (spread.insert(own.data).second) {
                  unread.push_back(own.data);
                }
              });
    }
  }

  ArrayRef<DataType> cells() const { return order; }
  int64_t stateOf(DataType cell) const { return states.lookup(cell); }

private:
  SmallVector<DataType> order;
  DenseMap<DataType, int64_t> states;
};

// A path through a step: where its code goes, what it has still to drop,
// the next part last, and the own cells it leaves to the loop.
struct Path {
  Block *block;
  SmallVector<Part> parts;
  SmallVector<LaterPart> later;
};

// Whether a path goes on, or split where a constructor was read: one path
// per constructor then goes on with the rest of what its path had.
enum class Next : std::uint8_t { Goes, Splits };

// The code of a walk's steps. A step gives the next as the cell it frees,
// its state, and the newest cell left on the frame stack.
class Steps {
public:
  Steps(OpBuilder &b, Location loc, const Runtime &runtime, const Layouts &layouts,
        const Walk &walk)
      : b(b), loc(loc), runtime(runtime), layouts(layouts), walk(walk),
        ptr(ptrType(b.getContext())), word(b.getI64Type()) {
    // An own cell left on the frame stack: the cell, the entry pushed before
    // it and the cell's state, a word each.
    unsigned at = 0;
    for (Type type : {ptr, ptr, word}) {
      entry.push_back(layout::Slot{{type, layout::Word::Uncounted}, at});
      at += layouts.sizeOf(type);
    }
    entryBytes = static_cast<int64_t>(llvm::alignTo(at, cellAlignment()));
  }

  SmallVector<Type> types() const { return {ptr, word, ptr}; }

  // The step that drops `first` at the end of `block`, `left` the newest
  // cell on the frame stack, every path it splits into ending in an
  // scf.yield of the next step.
  void step(Block *block, Part first, Value left) const {
    SmallVector<Path> paths;
    paths.push_back(Path{block, {std::move(first)}, {}});
    while (!paths.empty()) {
      Path path = paths.pop_back_val();
      b.setInsertionPointToEnd(path.block);
      if (advance(path, paths) == Next::Goes)
        finish(path.later, left);
    }
  }

  // The step that takes the newest cell left on the frame stack, `left`:
  // read out of its entry, which is then given back.
  void pop(Block *block, Value left) const {
    b.setInsertionPointToEnd(block);
    SmallVector<Value> waiting = runtime.load(b, loc, left, cellAlignment(), entry);
    runtime.call(b, loc, idr::runtime::helper::framePop, left);
    scf::YieldOp::create(b, loc, ValueRange{waiting[0], waiting[2], waiting[1]});
  }

private:
  // A path's parts dropped in order, until one splits it.
  Next advance(Path &path, SmallVectorImpl<Path> &paths) const {
    while (!path.parts.empty()) {
      Next next = idr::match(
          path.parts.pop_back_val(),
          [&](ByCountPart counted) {
            runtime.dec(b, loc, counted.components, counted.values);
            return Next::Goes;
          },
          [&](LaterPart later) {
            path.later.push_back(later);
            return Next::Goes;
          },
          [&](UnreadPart unread) { return read(std::move(unread), path, paths); },
          [&](ReadPart known) {
            expand(std::move(known), path.parts);
            return Next::Goes;
          });
      if (next == Next::Splits)
        return next;
    }
    return Next::Goes;
  }

  // A value whose constructor is still to be read: the one its type leaves
  // possible, with no read; or its tag read and its path split, one per
  // constructor, the last the switch's default, which is not tested for.
  Next read(UnreadPart unread, Path &path, SmallVectorImpl<Path> &paths) const {
    const families::TagSet &tags = unread.data.possibleTags();
    if (tags.size() == 1) {
      path.parts.push_back(ReadPart{unread.data, std::move(unread.where), tags.front()});
      return Next::Goes;
    }
    Value tag = idr::match(
        unread.where,
        [&](const InCell &in) {
          return runtime.loadTag(b, loc, in.cell, unread.data, contentsOf(unread.data));
        },
        [&](const InWords &in) -> Value {
          return LLVM::ZExtOp::create(b, loc, word, in.words.front());
        });
    Value index = arith::IndexCastOp::create(b, loc, b.getIndexType(), tag);
    SmallVector<int64_t> cases;
    for (size_t at = 0; at + 1 < tags.size(); ++at)
      cases.push_back(static_cast<uint32_t>(tags[at]));
    auto choose = scf::IndexSwitchOp::create(b, loc, types(), index, cases,
                                             static_cast<unsigned>(cases.size()));
    scf::YieldOp::create(b, loc, choose.getResults());
    auto branch = [&](Region &region, Tag known) {
      Path next{b.createBlock(&region), path.parts, path.later};
      next.parts.push_back(ReadPart{unread.data, unread.where, known});
      paths.push_back(std::move(next));
    };
    for (auto [at, region] : llvm::enumerate(choose.getCaseRegions()))
      branch(region, tags[at]);
    branch(choose.getDefaultRegion(), tags[tags.size() - 1]);
    return Next::Splits;
  }

  // The fields of a value whose constructor is known, as the parts the walk
  // meets next. A cell's are read out and the cell freed; an atom's cell is
  // static. A field the claim says nothing of is dropped by its counts, an
  // own cell left to the loop, and an own value in place read in turn, after
  // the rest, so that splitting at its constructor copies the least. A
  // buffer whose storage the claim covers is freed here, by its cell, the
  // first word of its descriptor, with its count never read: as a reuse
  // token is where its elements hold no reference, and by the runtime's
  // release of a dead cell, which drops each element by its count, where
  // they hold references.
  void expand(ReadPart known, SmallVectorImpl<Part> &parts) const {
    ArrayRef<layout::SelfDrop> drops = layouts.ownCells(known.data).of(known.tag);
    SmallVector<SmallVector<layout::Component>> components;
    SmallVector<SmallVector<Value>> values;
    idr::match(
        known.where,
        [&](const InCell &in) {
          const layout::Cell &cell = layouts.cells(known.data).cell(known.tag);
          if (cell.fields.empty())
            return;
          for (ArrayRef<layout::Slot> slots : cell.fields) {
            components.emplace_back(slots.begin(), slots.end());
            values.push_back(
                runtime.load(b, loc, in.cell, cellAlignment(), slots, contentsOf(known.data)));
          }
          runtime.call(b, loc, idr::runtime::helper::freeToken, in.cell);
        },
        [&](const InWords &in) {
          const layout::SumLayout &sum = layouts.sum(known.data);
          for (unsigned field = 0, n = static_cast<unsigned>(drops.size()); field < n; ++field) {
            components.push_back(llvm::map_to_vector(sum.slotsOf(known.tag, field),
                                                     [&](unsigned at) { return sum.words[at]; }));
            values.push_back(unboxedField(sum, in.words, known.tag, field));
          }
        });
    SmallVector<Part> now, after;
    for (size_t field = 0; field < drops.size(); ++field)
      idr::match(
          drops[field],
          [&](layout::ByCount) {
            now.push_back(ByCountPart{std::move(components[field]), std::move(values[field])});
          },
          [&](layout::FreeStorage) {
            runtime.call(b, loc, idr::runtime::helper::freeToken, values[field].front());
          },
          [&](layout::ReleaseStorage) {
            runtime.call(b, loc, idr::runtime::helper::releaseDead, values[field].front());
          },
          [&](const layout::OwnCell &own) {
            if (own.data.layout() == Layout::Cell)
              now.push_back(LaterPart{values[field].front(), walk.stateOf(own.data)});
            else
              after.push_back(UnreadPart{own.data, InWords{std::move(values[field])}});
          });
    parts.append(std::make_move_iterator(after.rbegin()), std::make_move_iterator(after.rend()));
    parts.append(std::make_move_iterator(now.rbegin()), std::make_move_iterator(now.rend()));
  }

  // The end of a path: the first own cell it leaves is the next step's, the
  // rest pushed onto the frame stack above `left`; with none, the next step
  // takes the newest cell left there.
  void finish(ArrayRef<LaterPart> later, Value left) const {
    if (later.empty()) {
      Value nothing = LLVM::PoisonOp::create(b, loc, ptr);
      scf::YieldOp::create(b, loc, ValueRange{nothing, i64Constant(b, loc, 0), left});
      return;
    }
    for (const LaterPart &waiting : later.drop_front()) {
      Value pushed =
          runtime.call(b, loc, idr::runtime::helper::framePush, i64Constant(b, loc, entryBytes))
              .getResult();
      runtime.store(b, loc, pushed, cellAlignment(), entry,
                    ValueRange{waiting.cell, left, i64Constant(b, loc, waiting.state)});
      left = pushed;
    }
    scf::YieldOp::create(
        b, loc, ValueRange{later.front().cell, i64Constant(b, loc, later.front().state), left});
  }

  OpBuilder &b;
  Location loc;
  const Runtime &runtime;
  const Layouts &layouts;
  const Walk &walk;
  Type ptr, word;
  SmallVector<layout::Slot> entry;
  int64_t entryBytes;
};

// The drop of a value of `data` its type claims `unique self`, at `where`:
// the first step, then the loop of the rest while a step leaves a cell to
// free or one waits on the frame stack, each step by its state.
void dropOwn(OpBuilder &b, Location loc, const Runtime &runtime, const Layouts &layouts,
             DataType data, Where where) {
  Walk walk(layouts, data);
  Steps steps(b, loc, runtime, layouts, walk);
  SmallVector<Type> types = steps.types();
  Value none = LLVM::ZeroOp::create(b, loc, ptrType(b.getContext()));
  auto first = scf::ExecuteRegionOp::create(b, loc, types);
  {
    OpBuilder::InsertionGuard guard(b);
    steps.step(b.createBlock(&first.getRegion()), UnreadPart{data, std::move(where)}, none);
  }
  ArrayRef<DataType> cells = walk.cells();
  if (cells.empty())
    return;
  auto loop = scf::WhileOp::create(b, loc, types, first.getResults(), nullptr, nullptr);
  OpBuilder::InsertionGuard guard(b);
  Block &before = loop.getBefore().front();
  b.setInsertionPointToEnd(&before);
  Value freeing = LLVM::ICmpOp::create(b, loc, LLVM::ICmpPredicate::ne, before.getArgument(1),
                                       i64Constant(b, loc, 0));
  Value waiting = LLVM::ICmpOp::create(b, loc, LLVM::ICmpPredicate::ne, before.getArgument(2),
                                       LLVM::ZeroOp::create(b, loc, ptrType(b.getContext())));
  scf::ConditionOp::create(b, loc, LLVM::OrOp::create(b, loc, freeing, waiting),
                           before.getArguments());
  Block &after = loop.getAfter().front();
  b.setInsertionPointToEnd(&after);
  Value cell = after.getArgument(0), left = after.getArgument(2);
  Value index = arith::IndexCastOp::create(b, loc, b.getIndexType(), after.getArgument(1));
  SmallVector<int64_t> states =
      llvm::to_vector(llvm::seq<int64_t>(0, static_cast<int64_t>(cells.size())));
  auto choose = scf::IndexSwitchOp::create(b, loc, types, index, states,
                                           static_cast<unsigned>(states.size()));
  scf::YieldOp::create(b, loc, choose.getResults());
  MutableArrayRef<Region> byState = choose.getCaseRegions();
  steps.pop(b.createBlock(&byState.front()), left);
  for (auto [region, own] : llvm::zip_equal(byState.drop_front(), cells.drop_back()))
    steps.step(b.createBlock(&region), UnreadPart{own, InCell{cell}}, left);
  steps.step(b.createBlock(&choose.getDefaultRegion()), UnreadPart{cells.back(), InCell{cell}},
             left);
}

} // namespace

void dropValue(OpBuilder &b, Location loc, const Runtime &runtime, const Layouts &layouts,
               Type type, ValueRange value) {
  auto data = dyn_cast<DataType>(unrestricted(type));
  if (data && claims(type, Unique::Self)) {
    switch (data.layout()) {
    case Layout::Cell:
      return dropOwn(b, loc, runtime, layouts, data, InCell{value.front()});
    case Layout::InPlace:
      return dropOwn(b, loc, runtime, layouts, data, InWords{SmallVector<Value>(value)});
    // A number's word, a natural's and a frame stack's hold no cell of the
    // value's own family.
    case Layout::Word8:
    case Layout::Word16:
    case Layout::Word32:
    case Layout::Word64:
    case Layout::Natural:
    case Layout::FrameStack:
      break;
    }
  }
  runtime.dec(b, loc, layouts.components(type), value);
}

} // namespace idr::conversion
