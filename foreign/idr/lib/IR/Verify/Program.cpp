// The rules of the module, which the dialect runs through `idr.program`
// before the ops inside are verified, so they assume nothing their
// verifiers check: one root, every sum or box type naming a declaration of
// its kind, and the containment of the declarations. What one function
// does with its values is its own verifier's.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/TypeGraph.h"
#include "idr/IR/Verify.h"

#include "mlir/IR/AttrTypeSubElements.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "llvm/ADT/DenseMap.h"

using namespace mlir;
using namespace idr;

LogicalResult idr::verify::program(ModuleOp module) {
  // One root, which is the only public function, of one of the two kinds.
  SmallVector<FuncOp> roots;
  for (auto fn : module.getOps<FuncOp>())
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

  // Containment through unboxed sums is acyclic, so every cycle of types
  // passes through a box: an unboxed sum is stored where it is, and one
  // that holds itself would have no size.
  TypeGraph graph(module.getOperation());
  SmallVector<DataOp> selfContained = graph.containsItself();
  if (!selfContained.empty())
    return selfContained.front().emitOpError("contains itself through unboxed sums; a recursive "
                                       "type must be declared box");
  return knots(module, graph);
}
