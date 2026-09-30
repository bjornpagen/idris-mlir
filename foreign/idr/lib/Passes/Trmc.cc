// idr-trmc: a self call whose result is a field of the boxed constructor
// a tail position returns becomes a tail call that writes the field.
//
// `copy (Cons x xs) = Cons x (copy xs)` returns through every level of
// the list. The constructor can be built before the call, with the field
// pending, and the call given the field as a destination (`!idr.dest`) to
// write once it has its value; then the call is the last thing the tail
// does. The function keeps its signature and does that for its first
// level only: each such tail builds its constructor, calls a clone with
// the destination and returns the constructor. The clone takes a
// destination and returns nothing: a tail of its own that builds a
// constructor around a self call writes the constructor to the
// destination it was given and calls itself with the new one, a plain self
// tail call passes the destination on, and any other tail writes its
// value. idr-tail-loops then makes the clone a loop, and the structure is
// written top down in constant stack. A self call in any other position
// (one whose result is inspected, as a rebalancing insert inspects its
// subtree) stays a call of the function, and the stack grows with it, as
// it must.
//
// A tail position is the function's return, or the yield of a region of a
// match right before a tail position's terminator whose results it passes
// on. The constructor is an idr.con or idr.reuse right before the
// terminator, and the call is before it with only ops between them that
// neither touch memory nor can fail, which the call then moves past: the
// call's result has no other use.

#include "idr/Idr.h"

#include "mlir/IR/IRMapping.h"
#include "mlir/IR/SymbolTable.h"

using namespace mlir;

namespace idr {
#define GEN_PASS_DEF_IDRTRMC
#include "idr/Passes.h.inc"
} // namespace idr

namespace {

// Whether `op` is the constructor of a box: an idr.con or idr.reuse.
bool buildsBox(Operation *op) {
  return isa_and_nonnull<idr::ConOp, idr::ReuseOp>(op) && isa<idr::BoxType>(idr::unrestricted(op->getResult(0).getType()));
}

SymbolRefAttr ctorOf(Operation *op) {
  if (auto con = dyn_cast<idr::ConOp>(op))
    return con.getCtor();
  return cast<idr::ReuseOp>(op).getCtor();
}

OperandRange fieldsOf(Operation *op) {
  if (auto con = dyn_cast<idr::ConOp>(op))
    return con.getFields();
  return cast<idr::ReuseOp>(op).getFields();
}

bool isSelfCall(Operation *op, func::FuncOp fn) {
  auto call = dyn_cast_or_null<func::CallOp>(op);
  return call && call.getCallee() == fn.getSymName();
}

// Whether `terminator` ends a tail position and passes on exactly the
// results of the op before it.
bool passesOnPrevious(Operation *terminator) {
  Operation *prev = terminator->getPrevNode();
  return isa<func::ReturnOp, idr::YieldOp>(terminator) && prev &&
         llvm::equal(prev->getResults(), terminator->getOperands());
}

// The match in tail position right before `terminator`, or null.
Operation *tailMatch(Operation *terminator) {
  Operation *prev = terminator->getPrevNode();
  return passesOnPrevious(terminator) && isa_and_nonnull<idr::MatchOp, idr::MatchLitOp>(prev) ? prev
                                                                                          : nullptr;
}

// The blocks in tail position of `block`: itself, or through the match in
// tail position, the blocks of its regions.
void forTails(Block &block, function_ref<void(Block &)> f) {
  if (Operation *match = tailMatch(block.getTerminator())) {
    for (Region &region : match->getRegions())
      if (!region.empty())
        forTails(region.front(), f);
    return;
  }
  f(block);
}

// A tail modulo constructor: the self call whose result is field `index`
// of the constructor `built`, which the block's terminator passes on.
struct Modulo {
  func::CallOp call;
  Operation *built;
  unsigned index;
};

std::optional<Modulo> moduloAt(Block &block, func::FuncOp fn) {
  Operation *terminator = block.getTerminator();
  Operation *built = terminator->getPrevNode();
  if (!passesOnPrevious(terminator) || !buildsBox(built))
    return std::nullopt;
  for (auto [index, field] : llvm::enumerate(fieldsOf(built))) {
    auto call = field.getDefiningOp<func::CallOp>();
    if (!call || !isSelfCall(call, fn) || call->getBlock() != &block || !call->hasOneUse() ||
        call->getNumResults() != 1)
      continue;
    bool movable = true;
    for (Operation *op = call->getNextNode(); op != built; op = op->getNextNode())
      movable = movable && isMemoryEffectFree(op) && isSpeculatable(op);
    if (movable)
      return Modulo{call, built, static_cast<unsigned>(index)};
  }
  return std::nullopt;
}

// The terminator of `block` with no operands, in place of the one it has.
void endWithNothing(OpBuilder &b, Block &block) {
  Operation *terminator = block.getTerminator();
  b.setInsertionPoint(terminator);
  if (isa<func::ReturnOp>(terminator))
    func::ReturnOp::create(b, terminator->getLoc());
  else
    idr::YieldOp::create(b, terminator->getLoc(), ValueRange());
  terminator->erase();
}

// The destination-passing form of one tail: the constructor built with
// the field pending, the cell written to `hole` when there is one (in the
// clone), and the field's destination passed to the clone in the call's
// place after it. The cell is written after its own destination is taken:
// writing consumes the cell's reference.
void passDestination(OpBuilder &b, Modulo tail, func::FuncOp clone, Value hole) {
  Location loc = tail.call.getLoc();
  Value cell = tail.built->getResult(0);
  b.setInsertionPoint(tail.built);
  Value pending = idr::PendingOp::create(b, loc, tail.call.getResult(0).getType());
  unsigned first = tail.built->getNumOperands() - static_cast<unsigned>(fieldsOf(tail.built).size());
  tail.built->setOperand(first + tail.index, pending);
  b.setInsertionPointAfter(tail.built);
  SymbolRefAttr ctor = ctorOf(tail.built);
  // The destination is taken from a view of the cell, whose reference
  // then moves on: into the hole it fills, or out of the function.
  Value seen = idr::BorrowOp::create(b, loc, cell);
  Value dest = idr::DestOfOp::create(
      b, loc, idr::DestType::get(b.getContext(), idr::unrestricted(pending.getType())), seen,
      FlatSymbolRefAttr::get(ctor.getLeafReference()), b.getI64IntegerAttr(tail.index));
  if (hole)
    idr::DestWriteOp::create(b, loc, hole, cell);
  SmallVector<Value> operands(tail.call.getOperands());
  operands.push_back(dest);
  auto call = func::CallOp::create(b, loc, clone, operands);
  call->setDiscardableAttrs(tail.call->getDiscardableAttrDictionary());
  tail.call->erase();
}

// Rewrites the tails of `block` in the clone, which returns nothing:
// each writes what it would have returned to `hole`, or passes it on.
void rewriteClone(OpBuilder &b, Block &block, func::FuncOp fn, func::FuncOp clone, Value hole) {
  Operation *terminator = block.getTerminator();
  if (Operation *match = tailMatch(terminator)) {
    for (Region &region : match->getRegions())
      if (!region.empty())
        rewriteClone(b, region.front(), fn, clone, hole);
    OperationState state(match->getLoc(), match->getName());
    state.addOperands(match->getOperands());
    state.addAttributes(llvm::to_vector(match->getDiscardableAttrs()));
    state.propertiesAttr = match->getPropertiesAsAttribute();
    for (Region &region : match->getRegions())
      state.addRegion()->takeBody(region);
    b.setInsertionPoint(match);
    b.create(state);
    endWithNothing(b, block);
    match->erase();
    return;
  }
  if (std::optional<Modulo> tail = moduloAt(block, fn)) {
    passDestination(b, *tail, clone, hole);
    endWithNothing(b, block);
    return;
  }
  if (!isa<func::ReturnOp, idr::YieldOp>(terminator))
    return;
  if (Operation *prev = terminator->getPrevNode();
      passesOnPrevious(terminator) && isSelfCall(prev, fn)) {
    SmallVector<Value> operands(prev->getOperands());
    operands.push_back(hole);
    b.setInsertionPoint(prev);
    auto call = func::CallOp::create(b, prev->getLoc(), clone, operands);
    call->setDiscardableAttrs(prev->getDiscardableAttrDictionary());
    endWithNothing(b, block);
    prev->erase();
    return;
  }
  b.setInsertionPoint(terminator);
  idr::DestWriteOp::create(b, terminator->getLoc(), hole, terminator->getOperand(0));
  endWithNothing(b, block);
}

struct Trmc : idr::impl::IdrTrmcBase<Trmc> {
  void runOnOperation() override {
    ModuleOp module = getOperation();
    SymbolTable symbols(module);
    OpBuilder b(&getContext());
    for (auto fn : llvm::make_early_inc_range(module.getOps<func::FuncOp>())) {
      if (fn.isExternal() || fn.getNumResults() != 1 || !isa<idr::BoxType>(idr::unrestricted(fn.getResultTypes()[0])))
        continue;
      SmallVector<Modulo> tails;
      forTails(fn.getBody().front(), [&](Block &block) {
        if (std::optional<Modulo> tail = moduloAt(block, fn))
          tails.push_back(*tail);
      });
      if (tails.empty())
        continue;
      ++numFunctions;
      numTails += tails.size();

      b.setInsertionPointAfter(fn);
      auto clone = cast<func::FuncOp>(b.clone(*fn));
      clone.setSymName((fn.getSymName() + "$trmc").str());
      clone.setPrivate();
      clone->removeAttr("idr.clone");
      symbols.insert(clone);
      auto dest = idr::DestType::get(&getContext(), idr::unrestricted(fn.getResultTypes()[0]));
      unsigned arity = clone.getNumArguments();
      (void)clone.insertArgument(arity, dest, DictionaryAttr(), fn.getLoc());
      clone.removeResAttrsAttr();
      clone.setFunctionType(FunctionType::get(&getContext(), clone.getArgumentTypes(), {}));
      rewriteClone(b, clone.getBody().front(), fn, clone, clone.getArgument(arity));

      for (Modulo tail : tails)
        passDestination(b, tail, clone, Value());
    }
  }
};

} // namespace
