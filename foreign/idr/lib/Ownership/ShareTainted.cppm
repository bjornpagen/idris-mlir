// idr.ownership:sharetainted: the values a view of which takes a reference
// of its own, shared where they are consumed, before exclusivity's solver
// runs. Nothing here is exported: inferExclusive runs it.
export module idr.ownership:sharetainted;

import idr.mlir;
import idr.dialect;

import :callee;
import :followed;
import :useof;

using namespace mlir;

namespace idr::ownership {

namespace {

// The owned value a view was read from: through views (idr.borrow), fields
// (idr.field, the fields a match's region binds) and changes of quantity.
Value viewRoot(Value value) {
  for (;;) {
    if (auto arg = dyn_cast<BlockArgument>(value)) {
      auto match = dyn_cast<MatchOp>(arg.getOwner()->getParentOp());
      if (!match)
        return value;
      value = match.getScrutinee();
      continue;
    }
    Operation *def = value.getDefiningOp();
    if (isa_and_nonnull<BorrowOp, FieldOp, LinEnterOp, LinUseOp>(def)) {
      value = def->getOperand(0);
      continue;
    }
    return value;
  }
}

} // namespace

// Before the solver: a value some view of which takes a reference of its
// own (idr.dup, here or in a callee that borrows the value) has shared
// cells by the time it is consumed, whatever it alone reached when it was
// made. Its consuming use gets it shared (idr.share): the solver reads the
// shared value there, and the value itself keeps what its provenance
// proves, which its callee's or constructor's type must agree with.
void shareTainted(ModuleOp module) {
  SymbolTableCollection symbols;
  // Sharing changes no symbol: the calls find their callees in one table.
  SymbolScope scope(module, symbols.getSymbolTable(module));
  llvm::SetVector<Value> tainted;
  llvm::DenseMap<Operation *, SmallVector<unsigned>> borrowedRoots;
  module.walk([&](DupOp dup) {
    Value root = viewRoot(dup.getValue());
    if (followed(root))
      tainted.insert(root);
    auto arg = dyn_cast<BlockArgument>(root);
    auto fn = arg ? dyn_cast<func::FuncOp>(arg.getOwner()->getParentOp()) : func::FuncOp();
    if (fn && !isOwned(arg.getType()))
      borrowedRoots[fn].push_back(arg.getArgNumber());
  });
  module.walk([&](func::CallOp call) {
    func::FuncOp fn = callee(call, symbols);
    auto it = fn ? borrowedRoots.find(fn) : borrowedRoots.end();
    if (it == borrowedRoots.end())
      return;
    for (unsigned index : it->second)
      if (Value root = viewRoot(call.getArgOperands()[index]); followed(root))
        tainted.insert(root);
  });
  OpBuilder b(module.getContext());
  for (Value value : tainted)
    for (OpOperand &use : llvm::make_early_inc_range(value.getUses()))
      if (useOf(use) == Use::Consume) {
        b.setInsertionPoint(use.getOwner());
        use.set(ShareOp::create(b, use.getOwner()->getLoc(), value.getType(), value));
      }
}

} // namespace idr::ownership
