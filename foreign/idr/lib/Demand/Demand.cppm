// idr.demand: the promises a program can be asked to keep, checked on the
// grades idr-rc wrote.
//
// in-place: a function that takes a parameter of quantity 1 apart and
// builds in its cell rebuilds it in place with no runtime test only when it
// holds that cell alone. Linearity says the function uses the value once,
// not that its caller held it alone; that is each call's to keep, and the
// grade idr-rc proved at the call says whether it does.
export module idr.demand;

import idr.mlir;
import idr.dialect;

using namespace mlir;

namespace idr::demand {

namespace {

// The value `value` is, seen through the positions that hand it on as
// itself: a linear position (idr.lin.enter, idr.lin.use), a view of it
// (idr.borrow, which a match reads), and the default region of a match on
// it, which takes the scrutinee back at its type.
Value itself(Value value) {
  for (;;) {
    if (Operation *def = value.getDefiningOp()) {
      if (!isa<LinEnterOp, LinUseOp, BorrowOp>(def))
        return value;
      value = def->getOperand(0);
      continue;
    }
    auto arg = cast<BlockArgument>(value);
    auto match = dyn_cast_or_null<MatchOp>(arg.getOwner()->getParentOp());
    if (!match || arg.getParentRegion() != match.getDefaultRegion())
      return value;
    value = match.getScrutinee();
  }
}

// The parameters `fn` rebuilds in place: those of quantity 1 whose cell an
// idr.reuse builds in, with the token of an idr.take of the parameter.
SmallVector<unsigned> rebuilt(func::FuncOp fn) {
  SmallVector<unsigned> params;
  fn.walk([&](ReuseOp reuse) {
    auto take = reuse.getToken().getDefiningOp<TakeOp>();
    auto param = take ? dyn_cast<BlockArgument>(itself(take.getValue())) : BlockArgument();
    if (!param || param.getParentRegion() != &fn.getBody() || !isLinear(param.getType()))
      return;
    if (!llvm::is_contained(params, param.getArgNumber()))
      params.push_back(param.getArgNumber());
  });
  return params;
}

// A call that passes a value other than an exclusive one where a promise
// asks for one: the function it is in, the call, the operand, and the
// idr.dup that shared the value there, when one did.
struct Broken {
  func::FuncOp caller;
  func::CallOp call;
  unsigned index;
  DupOp dup;
};

void report(Broken broken) {
  Value value = broken.call.getOperand(broken.index);
  InFlightDiagnostic error = broken.call.emitError();
  error << "unsupported (uniqueness): @" << broken.caller.getSymName() << " passes a shared "
        << getSumName(value.getType()).getValue() << " to @" << broken.call.getCallee()
        << ", which rebuilds it in place";
  if (broken.dup)
    error.attachNote(broken.dup.getLoc()) << "shared here";
}

} // namespace

// Every call of a function passes each parameter the function rebuilds in
// place exclusive (`!idr.excl<T>`): an error at each call that passes it
// owned or as a view, with a note at the idr.dup that shared it, when the
// call passes one.
export LogicalResult inPlace(ModuleOp module) {
  DenseMap<StringAttr, SmallVector<unsigned>> promised;
  for (auto fn : module.getOps<func::FuncOp>())
    if (!fn.isExternal())
      if (SmallVector<unsigned> params = rebuilt(fn); !params.empty())
        promised[fn.getSymNameAttr()] = std::move(params);
  if (promised.empty())
    return success();

  SmallVector<Broken> broken;
  for (auto caller : module.getOps<func::FuncOp>())
    caller.walk([&](func::CallOp call) {
      auto found = promised.find(call.getCalleeAttr().getAttr());
      if (found == promised.end())
        return;
      for (unsigned index : found->second)
        if (!isExclusive(call.getOperand(index).getType()))
          broken.push_back(
              {caller, call, index, throughLinear(call.getOperand(index)).getDefiningOp<DupOp>()});
    });
  // The calls that share the value there come first, since the frontend
  // names the first error: each other one passes on a value such a call
  // shared (a function's call of itself on a part of what it took apart),
  // or one shared into the grade such a call set.
  for (Broken each : broken)
    if (each.dup)
      report(each);
  for (Broken each : broken)
    if (!each.dup)
      report(each);
  return success(broken.empty());
}

} // namespace idr::demand
