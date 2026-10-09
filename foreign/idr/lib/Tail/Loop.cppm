// idr.tail:loop: the general loop: the whole body of a function in the
// before region of an scf.while, with a payload at every tail position.
export module idr.tail:loop;

import idr.mlir;
import idr.dialect;
import idr.graph;

import :reaches;

using namespace mlir;

namespace idr::tail {

// The general loop: the whole body in the before region, with a payload at
// every tail position.
struct Loop {
  func::FuncOp fn;
  TypeRange args;
  TypeRange results;
  OpBuilder &b;

  // What a payload carries in the places the path that yields it does not
  // read: a ub.poison, a value of the program, which may be any value of
  // its type, as upstream passes one where an operand goes unread.
  SmallVector<Value> poison(Location loc, TypeRange types) {
    return llvm::map_to_vector(types, [&](Type type) -> Value {
      return ub::PoisonOp::create(b, loc, type);
    });
  }

  Value flag(Location loc, bool value) {
    return arith::ConstantOp::create(b, loc, b.getBoolAttr(value));
  }

  // Rewrites the tail of `block`, which ends in a tail position, to compute
  // the payload (continue, A, R), and returns it. The block's terminator,
  // whose operands may be dropped, is left for the caller to replace.
  SmallVector<Value> payload(Block &block) {
    Operation *terminator = block.getTerminator();
    Location loc = terminator->getLoc();
    Operation *prev = graph::passesOnPrevious(terminator) ? terminator->getPrevNode() : nullptr;
    SmallVector<Value> out;
    if (prev && graph::isSelfCall(prev, fn)) {
      b.setInsertionPoint(prev);
      out.push_back(flag(loc, true));
      llvm::append_range(out, prev->getOperands());
      llvm::append_range(out, poison(loc, results));
      prev->dropAllUses();
      prev->erase();
      return out;
    }
    if (prev && isTailMatch(prev) && reachesTailCall(block, fn))
      return SmallVector<Value>(rebuildMatch(prev)->getResults());
    b.setInsertionPoint(terminator);
    out.push_back(flag(loc, false));
    llvm::append_range(out, poison(loc, args));
    llvm::append_range(out, terminator->getOperands());
    return out;
  }

  // The match `op`, with results (continue, A, R) and each region yielding
  // its payload. Regions that end in `ub.unreachable` are left alone.
  Operation *rebuildMatch(Operation *op) {
    SmallVector<Type> types{b.getI1Type()};
    llvm::append_range(types, args);
    llvm::append_range(types, results);
    OperationState state(op->getLoc(), op->getName());
    state.addOperands(op->getOperands());
    state.addTypes(types);
    state.addAttributes(llvm::to_vector(op->getDiscardableAttrs()));
    state.propertiesAttr = op->getPropertiesAsAttribute();
    for (Region &region : op->getRegions())
      state.addRegion()->takeBody(region);
    b.setInsertionPoint(op);
    Operation *match = b.create(state);
    op->dropAllUses();
    op->erase();
    for (Region &region : match->getRegions()) {
      if (region.empty())
        continue;
      auto yield = dyn_cast<idr::YieldOp>(region.front().getTerminator());
      if (!yield)
        continue;
      SmallVector<Value> values = payload(region.front());
      b.setInsertionPoint(yield);
      idr::YieldOp::create(b, yield.getLoc(), values);
      yield.erase();
    }
    return match;
  }

  void build() {
    Block &entry = fn.getBody().front();
    Location loc = fn.getLoc();
    auto before = std::make_unique<Block>();
    for (BlockArgument arg : entry.getArguments())
      before->addArgument(arg.getType(), arg.getLoc());
    before->getOperations().splice(before->end(), entry.getOperations());
    for (auto [old, now] : llvm::zip(entry.getArguments(), before->getArguments()))
      old.replaceAllUsesWith(now);

    auto ret = cast<func::ReturnOp>(before->getTerminator());
    SmallVector<Value> values = payload(*before);
    b.setInsertionPoint(ret);
    scf::ConditionOp::create(b, ret.getLoc(), values.front(), ArrayRef(values).drop_front());
    ret.erase();
    if (!fn->hasAttr("idr.total")) {
      b.setInsertionPointToStart(before.get());
      idr::MayLoopOp::create(b, loc);
    }

    SmallVector<Type> carried(args);
    llvm::append_range(carried, results);
    b.setInsertionPointToEnd(&entry);
    auto loop = scf::WhileOp::create(b, loc, carried, entry.getArguments());
    loop.getBefore().push_back(before.release());
    Block *after = b.createBlock(&loop.getAfter(), loop.getAfter().end(), carried,
                                 SmallVector<Location>(carried.size(), loc));
    scf::YieldOp::create(b, loc, after->getArguments().take_front(args.size()));
    b.setInsertionPointToEnd(&entry);
    func::ReturnOp::create(b, loc, loop.getResults().drop_front(args.size()));
  }
};

} // namespace idr::tail
