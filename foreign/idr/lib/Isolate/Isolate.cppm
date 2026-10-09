// idr.isolate: idr-isolate, which gives the body of every idr.lambda and
// idr.delay a private function of its own and makes the op an idr.closure
// or an idr.suspend of it over the values the body uses from above.
//
// It goes innermost first: a lambda inside another is already a closure of
// its own function when the outer body is isolated, and the outer body then
// captures what that closure takes from above it. MLIR's isolation finds the
// captures, and clones into the body each constant it uses: a constant is
// code the function rebuilds, not a value the closure has to carry.
export module idr.isolate;

import idr.mlir;
import idr.dialect;

using namespace mlir;

namespace idr::isolate {

namespace {

// The Idris name in a location: Emit gives every function a NameLoc of its
// definition, inside a fused location for library code.
StringAttr nameIn(Location loc) {
  if (auto named = dyn_cast<NameLoc>(loc))
    return named.getName();
  if (auto fused = dyn_cast<FusedLoc>(loc))
    for (Location inner : fused.getLocations())
      if (StringAttr name = nameIn(inner))
        return name;
  return {};
}

// The results of the function a body becomes: the closure's, or the
// suspension's value. A body that never returns has them too.
SmallVector<Type> resultsOf(Operation *op) {
  if (auto lambda = dyn_cast<idr::LambdaOp>(op))
    return SmallVector<Type>(lambda.getType().getResults());
  return {cast<idr::LazyType>(idr::unrestricted(op->getResult(0).getType())).getValue()};
}

// What one function has had outlined from it: the number of bodies, which
// numbers the next one, and the last function made, which the next one
// follows, so that a function's code stays together in the order it is
// written.
struct Outlined {
  unsigned count = 0;
  Operation *last = nullptr;
};

} // namespace

} // namespace idr::isolate

export namespace idr::isolate {

// Outlines every idr.lambda and idr.delay of `module`. The function of a
// body in `f` is `<f>$lam<n>` or `<f>$delay<n>`, `n` counting `f`'s bodies in
// walk order, and its location names `f`'s Idris definition, by which
// idr-expect finds a definition's code wherever it was lifted to. Its code
// is `f`'s, so it breaks last when `f` does, and it is total: a body has no
// loop of its own, since a recursion goes through a function of the
// program, which carries its own proof or its absence. Fails, after an
// error, on an op outside a function, whose code would have no definition.
LogicalResult outline(ModuleOp module) {
  SmallVector<Operation *> bodies;
  module.walk<WalkOrder::PostOrder>([&](Operation *op) {
    if (isa<idr::LambdaOp, idr::DelayOp>(op))
      bodies.push_back(op);
  });
  MLIRContext *ctx = module.getContext();
  IRRewriter rewriter(ctx);
  SymbolTableCollection symbols;
  DenseMap<Operation *, Outlined> outlined;
  UnitAttr unit = UnitAttr::get(ctx);
  idr::IdrDialect::TotalAttrHelper total(ctx);
  idr::IdrDialect::BreakLastAttrHelper breakLast(ctx);
  for (Operation *op : bodies) {
    auto enclosing = op->getParentOfType<func::FuncOp>();
    if (!enclosing)
      return op->emitOpError("is outside a function, so its code has no definition");
    Operation *at = enclosing;
    Outlined &from = outlined.try_emplace(at, Outlined{0, at}).first->second;
    bool lambda = isa<idr::LambdaOp>(op);

    // Isolation appends the captures to the block's arguments; the function
    // takes them first, then the lambda's parameters.
    Region &body = op->getRegion(0);
    SmallVector<Value> captures =
        makeRegionIsolatedFromAbove(rewriter, body, [](Operation *def) {
          return isa<idr::ConstantOp, arith::ConstantOp>(def);
        });
    Block &isolated = body.front();
    size_t n = captures.size();
    SmallVector<BlockArgument> order;
    llvm::append_range(order, isolated.getArguments().take_back(n));
    llvm::append_range(order, isolated.getArguments().drop_back(n));
    SmallVector<Type> inputs;
    SmallVector<Location> locs;
    for (BlockArgument arg : order) {
      inputs.push_back(arg.getType());
      locs.push_back(arg.getLoc());
    }
    SmallVector<Type> results = resultsOf(op);

    std::string name =
        (enclosing.getSymName() + (lambda ? "$lam" : "$delay") + Twine(from.count++)).str();
    StringAttr definition = nameIn(enclosing.getLoc());
    auto fn = func::FuncOp::create(
        NameLoc::get(definition ? definition : enclosing.getSymNameAttr(), op->getLoc()), name,
        FunctionType::get(ctx, inputs, results));
    fn.setPrivate();
    total.setAttr(fn, unit);
    if (breakLast.isAttrPresent(enclosing))
      breakLast.setAttr(fn, unit);
    StringAttr symbol = symbols.getSymbolTable(enclosing->getParentOp())
                            .insert(fn, std::next(from.last->getIterator()));
    from.last = fn;

    Block *entry = rewriter.createBlock(&fn.getBody(), fn.getBody().end(), inputs, locs);
    SmallVector<Value> moved;
    llvm::append_range(moved, entry->getArguments().drop_front(n));
    llvm::append_range(moved, entry->getArguments().take_front(n));
    rewriter.mergeBlocks(&isolated, entry, moved);
    // The body's own yield returns; those of the matches in it stay theirs.
    if (auto yield = dyn_cast<idr::YieldOp>(entry->back())) {
      rewriter.setInsertionPoint(yield);
      rewriter.replaceOpWithNewOp<func::ReturnOp>(yield, yield.getResults());
    }

    rewriter.setInsertionPoint(op);
    auto callee = FlatSymbolRefAttr::get(symbol);
    Type type = op->getResult(0).getType();
    if (lambda)
      rewriter.replaceOpWithNewOp<idr::ClosureOp>(op, type, callee, captures);
    else
      rewriter.replaceOpWithNewOp<idr::SuspendOp>(op, type, callee, captures);
  }
  return success();
}

} // namespace idr::isolate
