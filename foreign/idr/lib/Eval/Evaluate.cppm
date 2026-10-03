// idr.eval:evaluate: what idr-eval does to a module: every closed call of a
// function that performs no IO is run, in rounds, and its results replace
// it as constants. Its closed calls are found, evaluated in a round when
// their outcome is not known yet, and replaced by their results.
export module idr.eval:evaluate;

import idr.mlir;
import idr.dialect;
import idr.facts;
import idr.support;

import :calls;
import :round;

using namespace mlir;

namespace idr::eval {

namespace {

// What a callee computes, as the cache knows it: a clone by its key (its
// owner and the patterns of what it fixed), which tells what it computes,
// any other function by its name. A clone's name does not: once the module
// no longer holds a clone, the next clone of its owner may take its name
// and compute something else.
Attribute calleeKey(func::FuncOp callee) {
  if (auto clone = callee->getAttrOfType<idr::CloneAttr>("idr.clone"))
    return clone.getKey();
  return FlatSymbolRefAttr::get(callee.getSymNameAttr());
}

// A call of code Idris does not prove terminating may never end, so one
// that does not costs the compilation well under a second.
constexpr Meter partialCode{
    {/*ticks=*/uint64_t{1} << 25, /*bytes=*/uint64_t{1} << 28, /*stack=*/uint64_t{1} << 28},
    "reaches code Idris does not prove terminating and did not finish",
};

// A call of total code ends, and gets room for what a program computes from
// its constants, bounded all the same.
constexpr Meter totalCode{
    {/*ticks=*/uint64_t{1} << 31, /*bytes=*/uint64_t{1} << 32, /*stack=*/uint64_t{1} << 30},
    "did not finish within the budget of total code",
};

// A closed call that may run now (idr.facts, canEvaluate).
std::optional<Call> closedCall(Operation *op, SymbolTable &symbols) {
  std::optional<idr::facts::Evaluation> evaluation = idr::facts::canEvaluate(op, symbols);
  if (!evaluation)
    return std::nullopt;
  return Call{op, evaluation->callee, ArrayAttr::get(op->getContext(), evaluation->args),
              evaluation->total ? &totalCode : &partialCode};
}

} // namespace

} // namespace idr::eval

export namespace idr::eval {

// Replaces every closed call in `module` whose outcome is known, from
// `cache` or from evaluating it now, by its results. Fails on an internal
// error only: a call that crashes or does not finish stays.
LogicalResult evaluate(ModuleOp module, Cache &cache, Statistics &stats, RunPipeline runPipeline) {
  SymbolTable symbols(module);
  llvm::MapVector<Key, SmallVector<Call>> calls;
  module.walk([&](Operation *op) {
    if (std::optional<Call> call = closedCall(op, symbols))
      calls[{calleeKey(call->callee), call->args}].push_back(*call);
  });
  SmallVector<Key> fresh;
  for (const auto &entry : calls)
    if (!cache.contains(entry.first))
      fresh.push_back(entry.first);
    else
      ++stats.cacheHits;
  if (!fresh.empty() && failed(evaluateRound(module, fresh, calls, cache, stats, runPipeline)))
    return failure();

  Dialect *dialect = module.getContext()->getLoadedDialect<idr::IdrDialect>();
  for (const auto &[key, sites] : calls) {
    const Outcome &outcome = cache.find(key)->second;
    if (outcome.stays)
      continue;
    for (const Call &call : sites)
      idr::support::perform<idr::support::EvalCallAction>(call.op, [&] {
        OpBuilder b(call.op);
        SmallVector<Value> values;
        for (auto [value, type] : llvm::zip_equal(outcome.results, call.op->getResultTypes()))
          values.push_back(dialect->materializeConstant(b, value, type, call.op->getLoc())->getResult(0));
        call.op->replaceAllUsesWith(values);
        call.op->erase();
        ++stats.evaluated;
      });
  }
  return success();
}

} // namespace idr::eval
