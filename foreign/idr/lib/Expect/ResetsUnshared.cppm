// resets-unshared: every take that may reuse a cell tests one its function
// never gives a second reference.
export module idr.expect:resetsUnshared;

import idr.mlir;
import idr.dialect;
import idr.ownership;

import :named;
import :report;

using namespace mlir;

namespace idr::expect {

namespace {

// Whether the function gives `value` a second reference: an idr.dup of a
// view of it, of the value it moved in from (idr.lin.enter, idr.lin.use),
// or of a value it was read from, whose cell then holds it shared.
bool givenSecondReference(Value value) noexcept {
  auto dupped = [](Value view) {
    return llvm::any_of(view.getUsers(), llvm::IsaPred<DupOp>);
  };
  for (; value; value = ownership::readFrom(value)) {
    for (Value alias = value; alias;) {
      if (dupped(alias))
        return true;
      for (Operation *user : alias.getUsers())
        if (auto borrow = dyn_cast<BorrowOp>(user); borrow && dupped(borrow.getResult()))
          return true;
      Operation *def = alias.getDefiningOp();
      alias = isa_and_nonnull<LinEnterOp, LinUseOp, BorrowOp>(def) ? def->getOperand(0) : Value();
    }
  }
  return false;
}

// The functions a property of functions is about: the ones `function`
// names, or, without one, every function with a body.
SmallVector<func::FuncOp> about(ModuleOp module, StringRef function, StringRef property) noexcept {
  if (!function.empty())
    return named(module, function, property);
  SmallVector<func::FuncOp> functions;
  for (auto fn : module.getOps<func::FuncOp>())
    if (!fn.isExternal())
      functions.push_back(fn);
  return functions;
}

} // namespace

// Every take of a box, in the function the argument names or
// in every function, tests a cell that its function never gives a second
// reference: no idr.dup of a view of the box or of a value it was read from.
export LogicalResult resetsUnshared(ModuleOp module, StringRef function) noexcept {
  constexpr StringRef property = "resets-unshared";
  SmallVector<func::FuncOp> functions = about(module, function, property);
  if (!function.empty() && functions.empty())
    return failure();
  bool held = true;
  for (func::FuncOp fn : functions)
    fn.walk([&](Operation *op) {
      Value cell;
      if (auto take = dyn_cast<TakeOp>(op); take && take.getToken())
        cell = take.getValue();
      if (!cell || !givenSecondReference(cell))
        return;
      fail(op->getLoc(), property) << op->getName() << " in " << where(op)
                                   << " tests a cell that its function gives a second reference";
      held = false;
    });
  return success(held);
}

} // namespace idr::expect
