// idr.verify:program: the rules of the module: its root, its declarations
// and types.
export module idr.verify:program;

import idr.mlir;
import idr.dialect;

import :cycles;
import :linearity;

using namespace mlir;
using namespace idr;

export namespace idr::verify {

// One root, the only public function, of type () -> i64 or
// (!idr.world) -> (...); every attribute read by someone; every sum or box
// type naming a declaration of its kind; containment through unboxed sums
// acyclic; no array that can hold a reference to itself; and the linearity
// of every function. Runs before the ops inside the module are verified, so it
// assumes nothing that their verifiers check.
LogicalResult program(ModuleOp module) {
  // One root, which is the only public function, of one of the two kinds.
  SmallVector<func::FuncOp> roots;
  for (auto fn : module.getOps<func::FuncOp>())
    if (fn.isPublic())
      roots.push_back(fn);
  if (roots.size() != 1)
    return module.emitOpError("expects exactly one public function (the root), found ")
           << roots.size();
  FunctionType root = roots.front().getFunctionType();
  Builder b(module.getContext());
  bool intRoot = root.getInputs().empty() && root.getNumResults() == 1 &&
                 root.getResult(0) == b.getI64Type();
  bool ioRoot = root.getInputs().size() == 1 && isWorld(root.getInput(0));
  if (!intRoot && !ioRoot)
    return roots.front().emitOpError("is the root, so its type must be () -> i64 or "
                                     "(!idr.world) -> (...), not ")
           << root;

  // Every attribute in the program is read by someone: an inherent one by
  // its op, a discardable one by its dialect or by one of our tools.
  WalkResult named = module.walk([&](Operation *op) -> WalkResult {
    if (op != module.getOperation() && failed(verifyDiscardableAttrs(op)))
      return WalkResult::interrupt();
    auto fn = dyn_cast<FunctionOpInterface>(op);
    if (!fn)
      return WalkResult::advance();
    auto check = [&](ArrayRef<DictionaryAttr> dicts, StringRef what) -> LogicalResult {
      for (auto [index, dict] : llvm::enumerate(dicts))
        for (NamedAttribute attr : dict ? dict.getValue() : ArrayRef<NamedAttribute>())
          if (!attr.getNameDialect())
            return fn->emitOpError("has the attribute ")
                   << attr.getName() << " on " << what << " " << index
                   << ", which no dialect defines";
      return success();
    };
    SmallVector<DictionaryAttr> args, results;
    fn.getAllArgAttrs(args);
    fn.getAllResultAttrs(results);
    if (failed(check(args, "argument")) || failed(check(results, "result")))
      return WalkResult::interrupt();
    return WalkResult::advance();
  });
  if (named.wasInterrupted())
    return failure();

  llvm::DenseMap<StringAttr, DataOp> datas;
  for (auto data : module.getOps<DataOp>())
    datas[data.getSymNameAttr()] = data;

  // Every sum or box type names a declaration of its kind. Whether one does
  // depends on the type alone, so one walker, which visits each attribute
  // and type once however many ops hold it, checks them all; `at` is the
  // op being walked, which an error names.
  Operation *at = nullptr;
  auto checkType = [&](Type type) -> WalkResult {
    Operation *op = at;
    auto check = [&](FlatSymbolRefAttr name, bool boxed) -> WalkResult {
      DataOp data = datas.lookup(name.getAttr());
      if (!data) {
        op->emitOpError("uses an undeclared data type ") << name;
        return WalkResult::interrupt();
      }
      if (data.getBox() != boxed) {
        op->emitOpError("uses ") << type << ", but " << name << " is declared "
                                 << (data.getBox() ? "box, so its values are !idr.box"
                                                   : "unboxed, so its values are !idr.data");
        return WalkResult::interrupt();
      }
      return WalkResult::advance();
    };
    if (auto data = dyn_cast<DataType>(type))
      return check(data.getName(), false);
    if (auto box = dyn_cast<BoxType>(type))
      return check(box.getName(), true);
    return WalkResult::advance();
  };
  AttrTypeWalker walker;
  walker.addWalk(checkType);
  WalkResult types = module.walk([&](Operation *op) -> WalkResult {
    at = op;
    if (walker.walk(op->getAttrDictionary()).wasInterrupted())
      return WalkResult::interrupt();
    for (Type type : op->getResultTypes())
      if (walker.walk(type).wasInterrupted())
        return WalkResult::interrupt();
    for (Region &region : op->getRegions())
      for (Block &block : region)
        for (Type type : block.getArgumentTypes())
          if (walker.walk(type).wasInterrupted())
            return WalkResult::interrupt();
    return WalkResult::advance();
  });
  if (types.wasInterrupted())
    return failure();

  // Containment through unboxed sums is acyclic, so
  // every cycle of types passes through a box.
  enum class Mark { Open, Done };
  llvm::DenseMap<DataOp, Mark> marks;
  std::function<LogicalResult(DataOp)> visit = [&](DataOp data) -> LogicalResult {
    if (!data)
      return success();
    auto [it, fresh] = marks.try_emplace(data, Mark::Open);
    if (!fresh && it->second == Mark::Open)
      return data.emitOpError("contains itself through unboxed sums; a recursive "
                              "type must be declared box");
    if (!fresh)
      return success();
    for (auto ctor : data.getBody().getOps<CtorOp>()) {
      ArrayAttr fields = ctor.getFieldTypesAttr();
      for (Attribute field : fields ? fields.getValue() : ArrayRef<Attribute>()) {
        auto type = dyn_cast<TypeAttr>(field);
        auto sum = type ? dyn_cast<DataType>(type.getValue()) : nullptr;
        if (sum && failed(visit(datas.lookup(sum.getName().getAttr()))))
          return failure();
      }
    }
    marks[data] = Mark::Done;
    return success();
  };
  for (auto data : module.getOps<DataOp>())
    if (failed(visit(data)))
      return failure();
  if (failed(cycles(module)))
    return failure();
  for (auto fn : module.getOps<FunctionOpInterface>())
    if (failed(linearity(fn)))
      return failure();
  return success();
}

} // namespace idr::verify
