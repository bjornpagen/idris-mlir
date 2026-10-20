// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Reset/reuse insertion's decisions, on functional code whose match
// regions end in their join point, after idr-rc made every boxed
// constructor with fields a cell and its init, and put on the stack the
// cells that stay in their frame.
//
// In a case region of a match on a box that is dead after the match, the
// box's constructor is known, so is its cell's size. whereDies finds where
// the box dies on each path of the region: after its last use there, or,
// when that use decides (a match), inside each of its regions. A last
// use that consumes the box (a call, a constructor) is where it dies, and
// its cell goes with it: nothing is taken on that path. Elsewhere `fits`
// looks ahead on the same path for the first fresh heap cell of the same
// size, going into the regions of the ops that decide, and recycles the
// dead box's cell for it instead: idr.take where the box dies, and
// idr.cell.recycle of its token in place of the idr.cell.new.
// idr-rc-grades makes both; placement then drops the token on the paths
// that do not recycle it. Inner matches are done first, so that their
// scrutinees, which die later, get the cells made after them.
//
// A box that is static, borrowed, built in a cell of the frame
// (idr.cell.stack) or a memo cell is left alone: its cell is not the
// program's to recycle. A cell of the frame is never recycled either, as
// only an idr.cell.new is a candidate.
//
// Each decision is taken on the function as the takes before it leave it:
// a take gives the reads of the box's fields after it fields of its own,
// and a box that is then only read, which a later decision may take apart,
// is that field. Nothing is rewritten here, so the moves are kept beside
// the function: which uses each take will have moved, and to which of its
// fields.
#include "idr/Analysis/Ownership.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Ownership.h"
#include "idr/IR/Symbols.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/Threading.h"
#include "llvm/ADT/Sequence.h"

#include <variant>

using namespace mlir;
using namespace idr::ownership;

namespace idr {

namespace {

using Site = Reuses::Site;
using TakenField = Reuses::TakenField;

// A box as the rewrite will find it: a value of the function, or a field
// of an earlier site's take.
using Held = std::variant<Value, TakenField>;

// A field of a site's take: its type, and the uses the take gives it.
struct Virtual {
  Type type;
  SmallVector<OpOperand *> uses;
};

class Decider {
public:
  Decider(FuncOp fn, const Layouts &layouts) : fn(fn), layouts(layouts) {}

  SmallVector<Site> run() {
    SmallVector<MatchOp> matches;
    fn.walk([&](MatchOp match) { matches.push_back(match); });
    for (MatchOp match : matches) {
      Value box = match.getScrutinee();
      if (!isa<BoxType>(unrestricted(box.getType())) || !reusable(box) || usedAfter(box, match))
        continue;
      DataType data = dataTypeOf(box.getType());
      for (unsigned index : llvm::seq(match.getNumCases())) {
        Block &body = match.getCaseRegion(index).front();
        dies(box, data, match.getCaseTag(index), body, body.getArguments());
      }
    }
    readBoxes();
    return std::move(sites);
  }

private:
  // A box that no match takes apart, whose every use reads a field of one
  // constructor: a read directly in a block proves the constructor from
  // there on, so the box dies in that block as a matched one does. The
  // boxes are found once the matched boxes are decided, the fields their
  // takes give among them, in the order a walk would meet them.
  void readBoxes() {
    for (auto [index, site] : llvm::enumerate(sites))
      takesAt[site.point].push_back(static_cast<unsigned>(index));
    visit(fn.getBody().front());
    for (auto [box, first] : boxes)
      dies(box, first.getDataType(), first.getTag(), *first->getBlock(), {});
  }

  // Each value of `block` as a post-order walk meets it, a take's fields
  // where the take will go. Takes at one point come last-made first, as
  // each is made right at the point.
  void visit(Block &block) {
    SmallVector<unsigned> atStart = takesAt.lookup(BlockStart{&block});
    for (unsigned site : llvm::reverse(atStart))
      considerTake(site);
    for (Operation &op : block) {
      for (Region &region : op.getRegions())
        for (Block &inner : region)
          visit(inner);
      for (Value result : op.getResults())
        if (isa<BoxType>(unrestricted(result.getType())))
          consider(result);
      SmallVector<unsigned> after = takesAt.lookup(After{&op});
      for (unsigned site : llvm::reverse(after))
        considerTake(site);
    }
  }

  void considerTake(unsigned site) {
    const Site &taken = sites[site];
    for (unsigned field : llvm::seq(static_cast<unsigned>(taken.data.getCtor(taken.tag).fields.size())))
      if (TakenField given{site, field}; virtuals.contains(given))
        consider(given);
  }

  void consider(Held box) {
    if (FieldOp first = onlyReads(typeOf(box), usesOf(box)); first && reusable(box))
      boxes.emplace_back(box, first);
  }

  // A value of the function, or a field a take gives: two kinds of box,
  // the one the IR holds and the one the rewrite will make.
  Type typeOf(const Held &box) const {
    if (const Value *value = std::get_if<Value>(&box))
      return value->getType();
    return virtuals.at(std::get<TakenField>(box)).type;
  }

  SmallVector<OpOperand *> usesOf(const Held &box) const {
    const Value *value = std::get_if<Value>(&box);
    if (!value)
      return virtuals.at(std::get<TakenField>(box)).uses;
    SmallVector<OpOperand *> uses;
    for (OpOperand &use : value->getUses())
      if (!moved.contains(&use))
        uses.push_back(&use);
    return uses;
  }

  // Whether `box` holds its own reference: not static data, nor read from
  // it (its lifetime says so), and not of the frame, whose cells the frame
  // lends. A take's field always does. Borrow inference keeps a parameter
  // that is taken apart owned. A memo cell is no one's to reuse: a force
  // writes it.
  bool reusable(const Held &box) {
    Type type = typeOf(box);
    return !isMemoCell(type) && lifetimeOf(type) == Lifetime::Heap;
  }

  // Where `box`, built by the constructor `tag` of `data`, whose fields
  // `bound` binds (when a match region does), dies on each path of
  // `block`, the first fresh heap cell after that point of the same size
  // gets the box's cell.
  void dies(Held box, DataType data, Tag tag, Block &block, ArrayRef<BlockArgument> bound) {
    // A box may be an atom, which has no cell: its take would hand out no
    // token to recycle.
    if (data.isAtom(tag))
      return;
    SmallVector<OpOperand *> uses = usesOf(box);
    unsigned size = layouts.box(data).cell(tag).size;
    // Reuses are decided before borrow inference grades the signatures,
    // so any call may take its arguments over.
    auto takesOver = [](OpOperand &use) { return isa<CallOp>(use.getOwner()) || consumes(use); };
    whereDies(uses, block, takesOver, [&](Block &where, Block::iterator at) {
      SmallVector<CellNewOp> found;
      if (fits(size, where, at, found))
        record(box, data, tag, where, at, bound, std::move(found), uses);
    });
  }

  // The first fresh heap cell on each path from `at` of `size` bytes, or
  // false when there is none. Only the regions of an op that decides are
  // on a path: any other runs its regions any number of times, so a cell
  // made there cannot take the one cell. A cell an earlier take has is a
  // recycled one already, and passed over.
  bool fits(unsigned size, Block &block, Block::iterator at, SmallVectorImpl<CellNewOp> &found) {
    for (Operation &op : llvm::make_range(at, block.end())) {
      if (auto cell = dyn_cast<CellNewOp>(op)) {
        CellType type = cell.getType();
        if (!claimed.contains(cell) &&
            layouts.box(type.getBox().getData()).cell(type.getTag()).size == size) {
          found.push_back(cell);
          return true;
        }
        continue;
      }
      if (!decides(&op))
        continue;
      // Every region is searched, each path finding its own constructor.
      if (llvm::count_if(op.getRegions(), [&](Region &region) {
            return !region.empty() && fits(size, region.front(), region.front().begin(), found);
          }) != 0)
        return true;
    }
    return false;
  }

  // A take of `box` at `at`, for the cells `found`: the site, and the uses
  // of its fields from that point on, which it will move.
  void record(Held box, DataType data, Tag tag, Block &where, Block::iterator at,
              ArrayRef<BlockArgument> bound, SmallVector<CellNewOp> found,
              ArrayRef<OpOperand *> uses) {
    auto index = static_cast<unsigned>(sites.size());
    claimed.insert(found.begin(), found.end());
    sites.push_back(Site{box, data, tag, pointBefore(where, at),
                         SmallVector<BlockArgument>(bound.begin(), bound.end()), std::move(found)});
    Type boxType = typeOf(box);
    ArrayRef<Type> fieldTypes = data.getCtor(tag).fields;
    for (ownership::Field field : fieldsOf(uses, tag, bound)) {
      TakenField given{index, field.index};
      SmallVector<OpOperand *> &moves =
          virtuals.try_emplace(given, Virtual{fieldType(boxType, fieldTypes[field.index]), {}})
              .first->second.uses;
      for (OpOperand &use : field.value.getUses())
        if (!moved.contains(&use) && heldIn(where, use, at)) {
          moved.try_emplace(&use, given);
          moves.push_back(&use);
        }
    }
  }

  FuncOp fn;
  const Layouts &layouts;
  SmallVector<Site> sites;
  // The cells a site recycles its cell for.
  DenseSet<Operation *> claimed;
  // Every use a site's take will move, and the field it moves to.
  DenseMap<OpOperand *, TakenField> moved;
  // The fields the takes give, each with the uses it moves.
  DenseMap<TakenField, Virtual> virtuals;
  // The matched sites, by where each take will go.
  DenseMap<Point, SmallVector<unsigned>> takesAt;
  SmallVector<std::pair<Held, FieldOp>> boxes;
};

} // namespace

// Each function's sites depend on its body, the data types and the
// layouts alone, so they are found in parallel, one slot per function.
Reuses::Reuses(Operation *program, AnalysisManager &am) {
  const Layouts &layouts = am.getAnalysis<Layouts>();
  SmallVector<FuncOp> functions(cast<ProgramOp>(program).getOps<FuncOp>());
  SmallVector<SmallVector<Site>> slots(functions.size());
  parallelForEach(program->getContext(), llvm::seq<size_t>(0, functions.size()), [&](size_t index) {
    slots[index] = Decider(functions[index], layouts).run();
  });
  for (auto [fn, found] : llvm::zip_equal(functions, slots))
    sitesOf[fn] = std::move(found);
}

} // namespace idr
