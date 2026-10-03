// idr.eval:scratch: the module a round lowers and compiles: the callees
// of its calls with what they reach, and a wrapper per call. Nothing here
// is exported.
export module idr.eval:scratch;

import idr.mlir;
import idr.dialect;

import :calls;

using namespace mlir;

namespace idr::eval {

// The name of the wrapper that makes call `i` of a round.
std::string evalName(size_t i) { return ("__idr_eval_" + Twine(i)).str(); }

// The callees and every function they reach, a wrapper per call that
// materializes its arguments and returns its results, and the declarations,
// in a module nested in the one being evaluated, where the pass can run its
// pipelines.
ModuleOp scratch(ModuleOp module, ArrayRef<Key> keys,
                 const llvm::MapVector<Key, SmallVector<Call>> &calls) {
  MLIRContext *ctx = module.getContext();
  OpBuilder b(ctx);
  b.setInsertionPointToEnd(module.getBody());
  ModuleOp copy = ModuleOp::create(b, module.getLoc());
  b.setInsertionPointToEnd(copy.getBody());
  for (auto data : module.getOps<idr::DataOp>())
    b.clone(*data);
  SymbolTable symbols(module);
  llvm::SetVector<func::FuncOp> reached;
  auto reach = [&](Attribute symbol) {
    if (auto name = dyn_cast<FlatSymbolRefAttr>(symbol))
      if (auto fn = symbols.lookup<func::FuncOp>(name.getAttr()))
        reached.insert(fn);
  };
  for (const Key &key : keys) {
    reached.insert(calls.find(key)->second.front().callee);
    Attribute args = key.second;
    args.walk([&](idr::ClosureAttr closure) { reach(closure.getCallee()); });
  }
  for (size_t i = 0; i < reached.size(); ++i)
    if (auto uses = SymbolTable::getSymbolUses(reached[i]))
      for (const SymbolTable::SymbolUse &use : *uses)
        reach(use.getSymbolRef());
  for (func::FuncOp fn : reached)
    cast<func::FuncOp>(b.clone(*fn)).setPrivate();
  Dialect *dialect = ctx->getLoadedDialect<idr::IdrDialect>();
  for (auto [i, key] : llvm::enumerate(keys)) {
    func::FuncOp callee = calls.find(key)->second.front().callee;
    FunctionType type = callee.getFunctionType();
    Location loc = calls.find(key)->second.front().op->getLoc();
    auto wrapper = func::FuncOp::create(b, loc, evalName(i), b.getFunctionType({}, type.getResults()));
    OpBuilder::InsertionGuard guard(b);
    b.setInsertionPointToStart(wrapper.addEntryBlock());
    SmallVector<Value> args;
    for (auto [value, input] : llvm::zip_equal(cast<ArrayAttr>(key.second), type.getInputs()))
      args.push_back(dialect->materializeConstant(b, value, input, loc)->getResult(0));
    auto call = func::CallOp::create(b, loc, callee.getSymName(), type.getResults(), args);
    func::ReturnOp::create(b, loc, call.getResults());
  }
  return copy;
}

} // namespace idr::eval
