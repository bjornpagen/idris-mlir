// A suspension's function may return a closure. After that return becomes
// a sum, every lazy type that still names the closure type names the sum.

module idr.defunctionalize;

import idr.mlir;
import idr.dialect;

using namespace mlir;

namespace idr::defunctionalize {

llvm::DenseMap<StringAttr, Type> Converter::suspensionResults() {
  llvm::DenseMap<StringAttr, Type> was;
  auto note = [&](StringAttr name) {
    func::FuncOp fn = module.function(name);
    if (!fn || fn.getNumResults() != 1)
      return;
    was.try_emplace(name, idr::unrestricted(fn.getResultTypes()[0]));
  };
  for (auto &entry : module.suspends)
    note(entry.first);
  for (auto &entry : module.suspendConstants)
    note(entry.first);
  return was;
}

Type Converter::adapt(Type type, const llvm::DenseMap<Type, Type> &next) {
  if (auto q = dyn_cast<idr::QType>(type)) {
    Type inner = adapt(q.getValue(), next);
    return inner == q.getValue() ? type : idr::graded(idr::gradeOf(type), inner);
  }
  if (auto lazy = dyn_cast<idr::LazyType>(type)) {
    Type inner = adapt(lazy.getValue(), next);
    if (Type found = next.lookup(inner))
      inner = found;
    return inner == lazy.getValue() ? type : idr::LazyType::get(inner);
  }
  auto fn = dyn_cast<idr::FnType>(type);
  if (!fn)
    return type;
  SmallVector<Type> inputs, outputs;
  bool changed = false;
  for (Type input : fn.getInputs()) {
    Type mapped = adapt(input, next);
    changed |= mapped != input;
    inputs.push_back(mapped);
  }
  for (Type output : fn.getResults()) {
    Type mapped = adapt(output, next);
    changed |= mapped != output;
    outputs.push_back(mapped);
  }
  return changed ? idr::FnType::get(type.getContext(), inputs, outputs) : type;
}

void Converter::adaptLazy(const llvm::DenseMap<StringAttr, Type> &was) {
  llvm::DenseMap<Type, Type> next;
  llvm::DenseSet<Type> ambiguous;
  for (auto &[name, oldType] : was) {
    func::FuncOp fn = module.function(name);
    if (!fn || fn.getNumResults() != 1 || ambiguous.contains(oldType))
      continue;
    Type now = idr::unrestricted(fn.getResultTypes()[0]);
    if (now == oldType)
      continue;
    auto [it, inserted] = next.try_emplace(oldType, now);
    if (!inserted && it->second != now) {
      next.erase(oldType);
      ambiguous.insert(oldType);
    }
  }
  if (next.empty())
    return;
  auto map = [&](Type type) { return adapt(type, next); };
  for (func::FuncOp fn : module.op.getOps<func::FuncOp>()) {
    SmallVector<Type> inputs, outputs;
    for (Type type : fn.getArgumentTypes())
      inputs.push_back(map(type));
    for (Type type : fn.getResultTypes())
      outputs.push_back(map(type));
    fn.setFunctionType(FunctionType::get(ctx, inputs, outputs));
  }
  module.op.walk([&](Operation *op) {
    for (Value result : op->getResults())
      result.setType(map(result.getType()));
    for (Region &region : op->getRegions())
      for (Block &block : region)
        for (BlockArgument arg : block.getArguments())
          arg.setType(map(arg.getType()));
  });
  module.op.walk([&](idr::CtorOp ctor) {
    SmallVector<Type> types;
    bool changed = false;
    for (Type type : ctor.getFieldTypes().getAsValueRange<TypeAttr>()) {
      Type mapped = map(type);
      changed |= mapped != type;
      types.push_back(mapped);
    }
    if (changed)
      ctor.setFieldTypesAttr(Builder(ctx).getTypeArrayAttr(types));
  });
}

} // namespace idr::defunctionalize
