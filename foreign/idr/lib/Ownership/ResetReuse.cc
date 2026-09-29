// Reset/reuse insertion (Counting Immutable Beans' R, D and S; Lean's
// ResetReuse), on functional code whose match regions end in their join
// point.
//
// In a case region of a match on a box that is dead after the match, the
// box's constructor is known, so is its cell's size. D finds where the box
// dies on each path of the region: after its last use there, or, when that
// use is a match, inside each of that match's regions. There S looks ahead
// on the same path for the first constructor of a box with a cell of the
// same size, going into the regions of the matches it meets, and builds it
// in the dead box's cell instead: idr.reset where the box dies, idr.reuse
// for the constructor. idr.rc then drops the token on the paths that do not
// reuse it. Inner matches are done first, so that their scrutinees, which
// die later, get the constructors built after them.
//
// A box that is static, borrowed or built in the stack frame
// (`idr.stack`) is left alone: its cell is not the program's to reuse.

#include "Ownership/Ownership.h"

#include "Lower/Layout.h"

using namespace mlir;

namespace idr::ownership {

namespace {

class Reuser {
public:
  Reuser(func::FuncOp fn, lower::Layouts &layouts) : fn(fn), layouts(layouts) {}

  std::pair<unsigned, unsigned> run() {
    SmallVector<MatchOp> matches;
    fn.walk([&](MatchOp match) { matches.push_back(match); });
    for (MatchOp match : matches) {
      Value box = match.getScrutinee();
      if (!isa<BoxType>(box.getType()) || !reusable(box) || usedAfter(box, match))
        continue;
      DataOp data = lookupData(match, box.getType());
      for (auto [index, name] : llvm::enumerate(match.getCases().getAsRange<FlatSymbolRefAttr>())) {
        CtorOp ctor = lookupCtor(data, name.getValue());
        Region &region = match.getCaseRegion(static_cast<unsigned>(index));
        if (ctor && !region.empty())
          dies(box, ctor, region.front(), nullptr);
      }
    }
    return {resets, reuses};
  }

private:
  // Whether `box` holds its own reference: not static, not borrowed (a
  // borrowed parameter, or a field read from one), not a stack cell.
  bool reusable(Value box) {
    for (Value value = box; value; value = readFrom(value)) {
      if (isStatic(value))
        return false;
      if (auto con = value.getDefiningOp<ConOp>(); con && con->hasAttr("idr.stack"))
        return false;
      if (auto arg = dyn_cast<BlockArgument>(value);
          arg && arg.getOwner()->getParentOp() == fn.getOperation() &&
          isBorrowed(fn, arg.getArgNumber()))
        return false;
    }
    return true;
  }

  // Whether `value` is used after `op`: later in its block, or after an op
  // that holds that block, up to the block that defines it.
  static bool usedAfter(Value value, Operation *op) {
    Block *home = value.getParentBlock();
    for (Operation *at = op; at; at = at->getParentOp()) {
      Block *block = at->getBlock();
      if (!block)
        return false;
      for (Operation *user : value.getUsers()) {
        Operation *top = block->findAncestorOpInBlock(*user);
        if (top && at->isBeforeInBlock(top))
          return true;
      }
      if (block == home || isa<func::FuncOp>(block->getParentOp()))
        return false;
    }
    return false;
  }

  // The ops of `block` after `after` (from its start when null) that use
  // `value`, themselves or in their regions, in order.
  static SmallVector<Operation *> usersIn(Value value, Block &block, Operation *after) {
    SmallVector<Operation *> users;
    for (Operation *user : value.getUsers()) {
      Operation *top = block.findAncestorOpInBlock(*user);
      if (top && (!after || after->isBeforeInBlock(top)))
        users.push_back(top);
    }
    llvm::sort(users, [](Operation *a, Operation *b) { return a->isBeforeInBlock(b); });
    users.erase(std::unique(users.begin(), users.end()), users.end());
    return users;
  }

  // D: `box`, built by `ctor`, is dead in `block` after `after`, which is
  // outside the block's region; find where it dies on each path.
  void dies(Value box, CtorOp ctor, Block &block, Operation *after) {
    SmallVector<Operation *> users = usersIn(box, block, after);
    if (users.empty()) {
      reset(box, ctor, block, block.begin());
      return;
    }
    Operation *last = users.back();
    if (last->hasTrait<OpTrait::IsTerminator>())
      return;
    if (last->getNumRegions() != 0) {
      for (Region &region : last->getRegions())
        if (!region.empty())
          dies(box, ctor, region.front(), nullptr);
      return;
    }
    reset(box, ctor, block, std::next(last->getIterator()));
  }

  // S: the first constructor on each path from `at` whose cell fits, or
  // false when there is none.
  bool fits(unsigned size, Block &block, Block::iterator at, SmallVectorImpl<ConOp> &found) {
    for (Operation &op : llvm::make_range(at, block.end())) {
      if (auto con = dyn_cast<ConOp>(op)) {
        if (isa<BoxType>(con.getType()) && !con->hasAttr("idr.stack"))
          if (CtorOp ctor = lookupCtor(con, con.getCtor()); ctor && layouts.box(ctor).size == size) {
            found.push_back(con);
            return true;
          }
        continue;
      }
      if (op.getNumRegions() == 0)
        continue;
      bool any = false;
      for (Region &region : op.getRegions())
        if (!region.empty() && fits(size, region.front(), region.front().begin(), found))
          any = true;
      if (any)
        return true;
    }
    return false;
  }

  void reset(Value box, CtorOp ctor, Block &block, Block::iterator at) {
    SmallVector<ConOp> found;
    if (!fits(layouts.box(ctor).size, block, at, found))
      return;
    OpBuilder b(&block, at);
    Location loc = at == block.end() ? block.getParentOp()->getLoc() : at->getLoc();
    auto name = SymbolRefAttr::get(ctor->getParentOfType<DataOp>().getSymNameAttr(),
                                   {FlatSymbolRefAttr::get(ctor.getSymNameAttr())});
    Value token = ResetOp::create(b, loc, TokenType::get(fn.getContext()), box, name);
    ++resets;
    for (ConOp con : found) {
      b.setInsertionPoint(con);
      auto reuse = ReuseOp::create(b, con.getLoc(), con.getType(), token, con.getCtor(),
                                   con.getFields());
      reuse->setDiscardableAttrs(con->getDiscardableAttrDictionary());
      con.replaceAllUsesWith(reuse.getResult());
      con.erase();
      ++reuses;
    }
  }

  func::FuncOp fn;
  lower::Layouts &layouts;
  unsigned resets = 0, reuses = 0;
};

} // namespace

std::pair<unsigned, unsigned> insertResetReuse(func::FuncOp fn, lower::Layouts &layouts) {
  return Reuser(fn, layouts).run();
}

} // namespace idr::ownership
