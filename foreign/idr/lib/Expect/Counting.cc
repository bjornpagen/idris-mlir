// reuses-in-place, counts-nothing, resets-unshared and reuses-every-cell:
// what reference counting left in a function, stated as the property a
// test wants of it rather than as the ops that show it.

#include "Expect/Expect.h"
#include "Ownership/Ownership.h"

#include "mlir/IR/Matchers.h"

using namespace mlir;

namespace idr::expect {

LogicalResult reusesInPlace(ModuleOp module, StringRef function) {
  constexpr StringRef property = "reuses-in-place";
  func::FuncOp fn = named(module, function, property);
  if (!fn)
    return failure();
  bool held = true, reused = false;
  fn.walk([&](Operation *op) {
    if (isa<ReuseOp>(op))
      reused = true;
    auto con = dyn_cast<ConOp>(op);
    if (con && isa<BoxType>(unrestricted(con.getType()))) {
      fail(op->getLoc(), property) << "a box of " << con.getCtor() << " gets a fresh cell in "
                                   << where(op);
      held = false;
    }
  });
  if (!reused) {
    fail(fn.getLoc(), property) << "nothing is built in a reused cell in " << where(fn);
    held = false;
  }
  return success(held);
}

LogicalResult countsNothing(ModuleOp module, StringRef function) {
  constexpr StringRef property = "counts-nothing";
  func::FuncOp fn = named(module, function, property);
  if (!fn)
    return failure();
  bool held = true;
  fn.walk([&](Operation *op) {
    if (!isa<DupOp, DropOp>(op))
      return;
    // Static data holds no count: a reference to it costs nothing.
    if (auto dup = dyn_cast<DupOp>(op); dup && matchPattern(dup.getValue(), m_Constant()))
      return;
    fail(op->getLoc(), property) << op->getName() << " in " << where(op);
    held = false;
  });
  return success(held);
}

LogicalResult testsNothing(ModuleOp module, StringRef function) {
  constexpr StringRef property = "tests-nothing";
  func::FuncOp fn = named(module, function, property);
  if (!fn)
    return failure();
  bool held = true, taken = false;
  fn.walk([&](Operation *op) {
    Value cell;
    if (auto take = dyn_cast<TakeOp>(op)) {
      taken = true;
      cell = take.getValue();
    } else if (auto reuse = dyn_cast<ReuseOp>(op)) {
      cell = reuse.getToken();
    }
    if (!cell || isExclusive(cell.getType()))
      return;
    fail(op->getLoc(), property) << op->getName() << " in " << where(op) << " tests a value of "
                                 << cell.getType() << ", which is not exclusive";
    held = false;
  });
  if (!taken) {
    fail(fn.getLoc(), property) << "nothing is taken apart in " << where(fn);
    held = false;
  }
  return success(held);
}

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

// The functions a property of functions is about: the one `function`
// names, or, without one, every function with a body.
SmallVector<func::FuncOp> about(ModuleOp module, StringRef function, StringRef property) noexcept {
  SmallVector<func::FuncOp> functions;
  if (!function.empty()) {
    if (func::FuncOp fn = named(module, function, property))
      functions.push_back(fn);
    return functions;
  }
  for (auto fn : module.getOps<func::FuncOp>())
    if (!fn.isExternal())
      functions.push_back(fn);
  return functions;
}

} // namespace

LogicalResult resetsUnshared(ModuleOp module, StringRef function) noexcept {
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

LogicalResult reusesEveryCell(ModuleOp module, StringRef function) noexcept {
  constexpr StringRef property = "reuses-every-cell";
  func::FuncOp fn = named(module, function, property);
  if (!fn)
    return failure();
  bool held = true;
  fn.walk([&](DropOp dec) {
    auto take = dec.getValue().getDefiningOp<TakeOp>();
    if (!take || dec.getValue() != take.getToken())
      return;
    SymbolRefAttr ctor = take.getCtor();
    // A constructor without fields is a static cell, never the program's
    // to reuse.
    if (CtorOp decl = lookupCtor(dec, ctor); decl && decl.getFieldTypes().empty())
      return;
    fail(dec.getLoc(), property) << "the cell of " << ctor << " is freed, not reused, in "
                                 << where(dec);
    held = false;
  });
  return success(held);
}

} // namespace idr::expect
