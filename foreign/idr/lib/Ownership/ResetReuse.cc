// Reset/reuse insertion (Counting Immutable Beans' R, D and S; Lean's
// ResetReuse), on functional code whose match regions end in their join
// point.
//
// In a case region of a match on a box that is dead after the match, the
// box's constructor is known, so is its cell's size. D finds where the box
// dies on each path of the region (whereDies): after its last use there,
// or, when that use is a match, inside each of that match's regions. A
// last use that consumes the box (a call, a constructor) is where it dies,
// and its cell goes with it: nothing is taken on that path. There S looks
// ahead on the same path for the first constructor of a box with a cell of
// the same size, going into the regions of the matches it meets, and
// builds it in the dead box's cell instead: idr.take where the box dies
// (takeAt), idr.reuse for the constructor. idr.rc then drops the token on
// the paths that do not reuse it. Inner matches are done first, so that
// their scrutinees, which die later, get the constructors built after
// them.
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
      if (!isa<BoxType>(unrestricted(box.getType())) || !reusable(box) || usedAfter(box, match))
        continue;
      DataOp data = lookupData(match, box.getType());
      for (auto [index, name] : llvm::enumerate(match.getCases().getAsRange<FlatSymbolRefAttr>())) {
        CtorOp ctor = lookupCtor(data, name.getValue());
        Region &region = match.getCaseRegion(static_cast<unsigned>(index));
        if (ctor && !region.empty())
          dies(box, ctor, region.front(), &region.front());
      }
    }
    readBoxes();
    return {takes, reuses};
  }

  // A box that no match takes apart, whose every use reads a field of one
  // constructor: a read directly in a block proves the constructor from
  // there on, so the box dies in that block as a matched one does.
  void readBoxes() {
    SmallVector<std::pair<Value, FieldOp>> boxes;
    fn.walk([&](Operation *op) {
      for (Value result : op->getResults())
        if (FieldOp first = onlyReads(result); first && reusable(result))
          boxes.emplace_back(result, first);
    });
    for (auto [box, first] : boxes) {
      auto name = SymbolRefAttr::get(getSumName(box.getType()).getAttr(), {first.getCtorAttr()});
      if (CtorOp ctor = lookupCtor(first, name))
        dies(box, ctor, *first->getBlock(), nullptr);
    }
  }

private:
  // Whether `box` holds its own reference: not static, not a stack cell.
  // Borrow inference runs after this and keeps a parameter that is taken
  // apart owned.
  bool reusable(Value box) {
    for (Value value = box; value; value = readFrom(value)) {
      if (isStatic(value))
        return false;
      if (auto con = value.getDefiningOp<ConOp>(); con && con->hasAttr("idr.stack"))
        return false;
    }
    return true;
  }

  // D and S: where `box`, built by `ctor`, whose fields `fields` binds (when
  // a match region does), dies on each path of `block`, the first
  // constructor after that point whose cell fits gets the box's cell.
  void dies(Value box, CtorOp ctor, Block &block, Block *fields) {
    whereDies(box, block, symbols, [&](Block &where, Block::iterator at) {
      reuseAt(ctor, where, at, [&] { return takeAt(box, ctor, where, at, fields).getToken(); });
    });
  }

  // S: the first constructor on each path from `at` whose cell fits, or
  // false when there is none. The body of a loop over an array runs once
  // per element, so a constructor in it cannot take the one cell.
  bool fits(unsigned size, Block &block, Block::iterator at, SmallVectorImpl<ConOp> &found) {
    for (Operation &op : llvm::make_range(at, block.end())) {
      if (auto con = dyn_cast<ConOp>(op)) {
        if (isa<BoxType>(unrestricted(con.getType())) && !con->hasAttr("idr.stack"))
          if (CtorOp ctor = lookupCtor(con, con.getCtor()); ctor && layouts.box(ctor).size == size) {
            found.push_back(con);
            return true;
          }
        continue;
      }
      if (op.getNumRegions() == 0 || isArrayLoop(&op))
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

  // The constructors that fit a cell of `ctor` after `at` get it, from the
  // token `token` makes there, if there are any.
  void reuseAt(CtorOp ctor, Block &block, Block::iterator at, function_ref<Value()> token) {
    SmallVector<ConOp> found;
    if (!fits(layouts.box(ctor).size, block, at, found))
      return;
    Value cell = token();
    ++takes;
    OpBuilder b(fn.getContext());
    for (ConOp con : found) {
      b.setInsertionPoint(con);
      auto reuse = ReuseOp::create(b, con.getLoc(), con.getType(), cell, con.getCtor(),
                                   con.getFields());
      reuse->setDiscardableAttrs(con->getDiscardableAttrDictionary());
      con.replaceAllUsesWith(reuse.getResult());
      con.erase();
      ++reuses;
    }
  }

  func::FuncOp fn;
  lower::Layouts &layouts;
  SymbolTableCollection symbols;
  unsigned takes = 0, reuses = 0;
};

} // namespace

std::pair<unsigned, unsigned> insertResetReuse(func::FuncOp fn, lower::Layouts &layouts) {
  return Reuser(fn, layouts).run();
}

} // namespace idr::ownership
