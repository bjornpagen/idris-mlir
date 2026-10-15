// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Reset/reuse insertion's decisions, on functional code whose match
// regions end in their join point.
//
// In a case region of a match on a box that is dead after the match, the
// box's constructor is known, so is its cell's size. whereDies finds where
// the box dies on each path of the region: after its last use there, or,
// when that use decides (a match), inside each of its regions. A last
// use that consumes the box (a call, a constructor) is where it dies, and
// its cell goes with it: nothing is taken on that path. Elsewhere `fits`
// looks ahead on the same path for the first constructor of a box with a
// cell of the same size, going into the regions of the ops that decide,
// and builds it in the dead box's cell instead: idr.take where the box dies,
// idr.reuse for the constructor. idr-rc-place makes both; placement then
// drops the token on the paths that do not reuse it. Inner matches are
// done first, so that their scrutinees, which die later, get the
// constructors built after them.
//
// A box that is static, borrowed, built in the stack frame (its con's
// `stack`) or a memo cell is left alone: its cell is not the program's to
// reuse.
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

// A field of an earlier site's take, by its position among the fields the
// takes gave.
struct VirtualField {
  unsigned index;
};

// A box as the rewrite will find it: a value of the function, or a field
// of an earlier site's take.
using Held = std::variant<Value, VirtualField>;

// A field of a site's take: its type, and the uses the take gives it.
struct Virtual {
  unsigned site, field;
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
      for (unsigned index : llvm::seq(static_cast<unsigned>(match.getCases().size()))) {
        Region &region = match.getCaseRegion(index);
        if (!region.empty())
          dies(box, data, match.getCaseTag(index), region.front(), region.front().getArguments());
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
    for (Block &block : fn.getBody())
      visit(block);
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
      if (auto it = virtualOf.find({site, field}); it != virtualOf.end())
        consider(VirtualField{it->second});
  }

  void consider(Held box) {
    if (FieldOp first = onlyReads(typeOf(box), usesOf(box)); first && reusable(box))
      boxes.emplace_back(box, first);
  }

  Type typeOf(const Held &box) const {
    if (const Value *value = std::get_if<Value>(&box))
      return value->getType();
    return virtuals[std::get<VirtualField>(box).index].type;
  }

  SmallVector<OpOperand *> usesOf(const Held &box) const {
    const Value *value = std::get_if<Value>(&box);
    if (!value)
      return virtuals[std::get<VirtualField>(box).index].uses;
    SmallVector<OpOperand *> uses;
    for (OpOperand &use : value->getUses())
      if (!moved.contains(&use))
        uses.push_back(&use);
    return uses;
  }

  // Whether `box` holds its own reference: not static, not a stack cell,
  // nor read from one. A take's field always does. Borrow inference keeps
  // a parameter that is taken apart owned. A memo cell is no one's to
  // reuse: a force writes it.
  bool reusable(const Held &box) {
    if (isMemoCell(typeOf(box)))
      return false;
    const Value *held = std::get_if<Value>(&box);
    if (!held)
      return true;
    // Up the chain of what each was read from.
    auto readThrough = [](Value value) -> std::optional<Value> {
      if (Value from = readFrom(value))
        return from;
      return std::nullopt;
    };
    return llvm::none_of(definitionChain(*held, readThrough), [](Value value) {
      auto con = value.getDefiningOp<ConOp>();
      return isStatic(value) || (con && con.getStack());
    });
  }

  // Where `box`, built by the constructor `tag` of `data`, whose fields
  // `bound` binds (when a match region does), dies on each path of
  // `block`, the first constructor after that point whose cell fits gets
  // the box's cell.
  void dies(Held box, DataType data, Tag tag, Block &block, ArrayRef<BlockArgument> bound) {
    // A constructor without fields is its atom: it has no cell, so its
    // take would hand out no token for a reuse to build in.
    if (data.getCtor(tag).fields.empty())
      return;
    SmallVector<OpOperand *> uses = usesOf(box);
    unsigned size = layouts.box(data, tag).size;
    // Reuses are decided before borrow inference grades the signatures,
    // so any call may take its arguments over.
    auto takesOver = [](OpOperand &use) { return isa<CallOp>(use.getOwner()) || consumes(use); };
    whereDies(uses, block, takesOver, [&](Block &where, Block::iterator at) {
      SmallVector<ConOp> found;
      if (fits(size, where, at, found))
        record(box, data, tag, where, at, bound, std::move(found), uses);
    });
  }

  // The first constructor on each path from `at` whose cell fits, or
  // false when there is none. Only the regions of an op that decides are
  // on a path: any other runs its regions any number of times, so a
  // constructor there cannot take the one cell. A constructor an earlier
  // take has is a reuse already, and passed over.
  bool fits(unsigned size, Block &block, Block::iterator at, SmallVectorImpl<ConOp> &found) {
    for (Operation &op : llvm::make_range(at, block.end())) {
      if (auto con = dyn_cast<ConOp>(op)) {
        Tag tag = con.getTag();
        if (!claimed.contains(con) && isa<BoxType>(unrestricted(con.getResult().getType())) &&
            !con.getStack() && !con.getDataType().getCtor(tag).fields.empty() &&
            layouts.box(con.getDataType(), tag).size == size) {
          found.push_back(con);
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

  // A take of `box` at `at`, for the constructors `found`: the site, and
  // the uses of its fields from that point on, which it will move.
  void record(Held box, DataType data, Tag tag, Block &where, Block::iterator at,
              ArrayRef<BlockArgument> bound, SmallVector<ConOp> found, ArrayRef<OpOperand *> uses) {
    auto index = static_cast<unsigned>(sites.size());
    std::variant<Value, Reuses::TakenField> taken;
    if (const Value *value = std::get_if<Value>(&box)) {
      taken = *value;
    } else {
      const Virtual &field = virtuals[std::get<VirtualField>(box).index];
      taken = Reuses::TakenField{field.site, field.field};
    }
    claimed.insert(found.begin(), found.end());
    sites.push_back(Site{taken, data, tag, pointBefore(where, at),
                         SmallVector<BlockArgument>(bound.begin(), bound.end()), std::move(found)});
    Type boxType = typeOf(box);
    ArrayRef<Type> fieldTypes = data.getCtor(tag).fields;
    for (Field field : fieldsOf(uses, tag, bound)) {
      unsigned virt = virtualFor(index, field.index, fieldType(boxType, fieldTypes[field.index]));
      for (OpOperand &use : field.value.getUses())
        if (!moved.contains(&use) && heldIn(where, use, at)) {
          moved[&use] = virt;
          virtuals[virt].uses.push_back(&use);
        }
    }
  }

  unsigned virtualFor(unsigned site, unsigned field, Type type) {
    auto [it, fresh] = virtualOf.try_emplace({site, field}, static_cast<unsigned>(virtuals.size()));
    if (fresh)
      virtuals.push_back(Virtual{site, field, type, {}});
    return it->second;
  }

  FuncOp fn;
  const Layouts &layouts;
  SmallVector<Site> sites;
  // The constructors a site builds in its cell.
  DenseSet<Operation *> claimed;
  // Every use a site's take will move, and the field it moves to.
  DenseMap<OpOperand *, unsigned> moved;
  SmallVector<Virtual> virtuals;
  DenseMap<std::pair<unsigned, unsigned>, unsigned> virtualOf;
  // The matched sites, by where each take will go.
  DenseMap<Point, SmallVector<unsigned>> takesAt;
  SmallVector<std::pair<Held, FieldOp>> boxes;
};

} // namespace

// Each function's sites depend on its body, the data types and the
// layouts alone, so they are found in parallel, one slot per function.
Reuses::Reuses(ProgramOp program, const Layouts &layouts) {
  SmallVector<FuncOp> functions(program.getOps<FuncOp>());
  SmallVector<SmallVector<Site>> slots(functions.size());
  parallelForEach(program->getContext(), llvm::seq<size_t>(0, functions.size()), [&](size_t index) {
    slots[index] = Decider(functions[index], layouts).run();
  });
  for (auto [fn, found] : llvm::zip_equal(functions, slots))
    sitesOf[fn] = std::move(found);
}

} // namespace idr
