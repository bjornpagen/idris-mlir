// The labels of a module: every function a closure or a suspension names,
// in its code and in its constants, with the captures it takes there.

module idr.layout;

import idr.mlir;
import idr.dialect;

using namespace mlir;

namespace idr::layout {

Layouts::Layouts(ModuleOp m) : module(m), target(m) {
  SymbolTable symbols(module);
  // A later note that the same label is a suspension sticks: a function
  // closure of it must not clear that, or the cell would be too small for
  // the value and the code pointer would never be replaced.
  auto note = [&](FlatSymbolRefAttr callee, unsigned captures, bool suspension) {
    auto key = std::make_pair(Attribute(callee), captures);
    auto fn = symbols.lookup<func::FuncOp>(callee.getAttr());
    if (!fn)
      return;
    auto [it, inserted] = labelIds.try_emplace(key, static_cast<unsigned>(labels.size()));
    if (inserted)
      labels.push_back({callee, captures, fn.getFunctionType(), suspension});
    else if (suspension)
      labels[it->second].suspension = true;
  };
  // A constant is a graph: a value it holds twice is one attribute, which
  // says the same of its labels wherever it sits, so it is read once.
  llvm::DenseSet<std::pair<Attribute, Type>> noted;
  auto noteValue = [&](auto &self, Attribute value, Type type) -> void {
    type = unrestricted(type);
    if (!noted.insert({value, type}).second)
      return;
    if (auto closure = dyn_cast<ClosureAttr>(value)) {
      note(closure.getCallee(), static_cast<unsigned>(closure.getCaptures().size()),
           isa<LazyType>(type));
      auto fn = symbols.lookup<func::FuncOp>(closure.getCallee().getAttr());
      if (!fn)
        return;
      for (auto [capture, arg] : llvm::zip(closure.getCaptures(), fn.getArgumentTypes()))
        self(self, capture, arg);
      return;
    }
    auto con = dyn_cast<ConAttr>(value);
    if (!con)
      return;
    auto data = symbols.lookup<DataOp>(con.getCtor().getRootReference());
    auto ctor = data ? data.lookupSymbol<CtorOp>(con.getCtor().getLeafReference()) : CtorOp();
    if (!ctor)
      return;
    for (auto [field, fieldType] :
         llvm::zip(con.getFields(), ctor.getFieldTypes().getAsValueRange<TypeAttr>()))
      self(self, field, fieldType);
  };
  module.walk<WalkOrder::PreOrder>([&](Operation *op) {
    if (auto closure = dyn_cast<ClosureOp>(op))
      note(closure.getCalleeAttr(), static_cast<unsigned>(closure.getCaptures().size()), false);
    if (auto suspend = dyn_cast<SuspendOp>(op))
      note(suspend.getCalleeAttr(), static_cast<unsigned>(suspend.getCaptures().size()), true);
    if (auto constant = dyn_cast<ConstantOp>(op))
      noteValue(noteValue, constant.getValue(), constant.getType());
    op->getAttrDictionary().walk([&](ClosureAttr closure) {
      note(closure.getCallee(), static_cast<unsigned>(closure.getCaptures().size()), false);
    });
  });
}

} // namespace idr::layout
