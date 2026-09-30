// Reset/reuse insertion (Counting Immutable Beans' R, D and S; Lean's
// ResetReuse), on functional code whose match regions end in their join
// point.
//
// In a case region of a match on a box that is dead after the match, the
// box's constructor is known, so is its cell's size. D finds where the box
// dies on each path of the region: after its last use there, or, when that
// use is a match, inside each of that match's regions. A last use that
// consumes the box (a call, a constructor) is where it dies, and its cell
// goes with it: nothing is taken on that path. There S looks ahead on the
// same path for the first constructor of a box with a cell of the same
// size, going into the regions of the matches it meets, and builds it in
// the dead box's cell instead: idr.take where the box dies, idr.reuse for
// the constructor. idr.rc then drops the token on the paths that do not
// reuse it. Inner matches are done first, so that their scrutinees, which
// die later, get the constructors built after them.
//
// The take moves the box's fields out of its cell, so the region's reads
// of a field after that point become the take's results: the field keeps
// the box's reference instead of taking one of its own where the region
// reads it, only for the box to drop it again when it dies. Reads before
// the take are borrowed from the box, which is still alive there.
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
        auto caseIndex = static_cast<unsigned>(index);
        Region &region = match.getCaseRegion(caseIndex);
        if (!ctor || region.empty())
          continue;
        // Dead from the region's start: its fields move out of it too.
        Block &entry = region.front();
        if (usersIn(box, entry, nullptr).empty())
          reuseAt(ctor, entry, entry.begin(),
                  [&] { return takeAtEntry(match, caseIndex).getToken(); });
        else
          dies(box, ctor, entry, nullptr, &entry);
      }
    }
    readBoxes();
    return {takes, reuses};
  }

  // A box that no match takes apart, whose every use reads a field of one
  // constructor (a nested pattern reads the fields of a box an outer one
  // matched): a read directly in a block proves the constructor from there
  // on, so the box dies in that block as a matched one does.
  void readBoxes() {
    SmallVector<std::pair<Value, FieldOp>> boxes;
    auto consider = [&](Value box) {
      if (!isa<BoxType>(unrestricted(box.getType())) || box.use_empty() || !reusable(box))
        return;
      FieldOp first;
      for (Operation *user : box.getUsers()) {
        auto read = dyn_cast<FieldOp>(user);
        if (!read || (first && read.getCtorAttr() != first.getCtorAttr()))
          return;
        if (!first || (read->getBlock() == first->getBlock() && read->isBeforeInBlock(first)))
          first = read;
      }
      Block *block = first->getBlock();
      for (Operation *user : box.getUsers()) {
        Operation *top = block->findAncestorOpInBlock(*user);
        if (!top || top->isBeforeInBlock(first))
          return;
      }
      boxes.emplace_back(box, first);
    };
    fn.walk([&](Operation *op) {
      for (Value result : op->getResults())
        consider(result);
    });
    for (auto [box, first] : boxes) {
      auto name = SymbolRefAttr::get(getSumName(box.getType()).getAttr(), {first.getCtorAttr()});
      if (CtorOp ctor = lookupCtor(first, name))
        dies(box, ctor, *first->getBlock(), nullptr, nullptr);
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

  // D: `box`, built by `ctor`, whose fields `fields` binds (when a match
  // region binds them), is dead in
  // `block` after `after`, which is outside the block's region; find where
  // it dies on each path.
  void dies(Value box, CtorOp ctor, Block &block, Operation *after, Block *fields) {
    SmallVector<Operation *> users = usersIn(box, block, after);
    if (users.empty()) {
      takeAt(box, ctor, block, block.begin(), fields);
      return;
    }
    Operation *last = users.back();
    if (last->hasTrait<OpTrait::IsTerminator>())
      return;
    // A last use that consumes the box moves its reference on, and the box
    // dies in it. A take after it would keep a second reference alive
    // across the use, so that whoever receives the box finds its cell
    // shared and copies it. Borrow inference runs later, so every call may
    // still consume its arguments here.
    if (consumes(box, last))
      return;
    if (last->getNumRegions() != 0) {
      for (Region &region : last->getRegions())
        if (!region.empty())
          dies(box, ctor, region.front(), nullptr, fields);
      return;
    }
    takeAt(box, ctor, block, std::next(last->getIterator()), fields);
  }

  bool consumes(Value box, Operation *op) {
    return llvm::any_of(op->getOpOperands(), [&](OpOperand &operand) {
      return operand.get() == box && useOf(operand, symbols) == Use::Consume;
    });
  }

  // S: the first constructor on each path from `at` whose cell fits, or
  // false when there is none.
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

  // An idr.take of `box` where it dies, whose fields replace the reads of
  // the box's fields after it: the arguments of `fields`, and idr.field.
  void takeAt(Value box, CtorOp ctor, Block &block, Block::iterator at, Block *fields) {
    reuseAt(ctor, block, at, [&] {
      OpBuilder b(&block, at);
      Location loc = at == block.end() ? block.getParentOp()->getLoc() : at->getLoc();
      auto name = SymbolRefAttr::get(ctor->getParentOfType<DataOp>().getSymNameAttr(),
                                     {FlatSymbolRefAttr::get(ctor.getSymNameAttr())});
      Counting counting(fn->getParentOfType<ModuleOp>());
      SmallVector<Type> results{owned(TokenType::get(fn.getContext()))};
      for (unsigned index = 0, e = static_cast<unsigned>(ctor.getFieldTypes().size()); index < e;
           ++index) {
        Type field = ctor.getFieldType(index);
        results.push_back(counting.counted(field) ? owned(field) : field);
      }
      auto take = TakeOp::create(b, loc, results, box, name);
      auto later = [&](OpOperand &use) {
        Operation *top = block.findAncestorOpInBlock(*use.getOwner());
        return top && take->isBeforeInBlock(top);
      };
      if (fields)
        for (auto [field, taken] : llvm::zip_equal(fields->getArguments(), take.getFields()))
          field.replaceUsesWithIf(taken, later);
      for (Operation *user : llvm::make_early_inc_range(box.getUsers()))
        if (auto read = dyn_cast<FieldOp>(user); read && read.getCtor() == ctor.getSymName())
          read.getResult().replaceUsesWithIf(
              take.getFields()[static_cast<unsigned>(read.getIndex())], later);
      return take.getToken();
    });
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
