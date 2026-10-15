// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The references of every function, from one walk of each body. A
// reference is a symbol use the module's table resolves to an idr.func:
// what a body may run while it runs, or names to be run later. A label
// constructor is named by its function, so a closure or a suspension made
// as data is a reference as it was before idr-defunctionalize; a plain
// constructor's name is no module symbol's. An idr.apply calls something
// and names no function, so it is not one.
//
// The bodies separate, so each is walked on a worker into its own slot:
// a worker reads its own body and the symbol table and writes its slot
// alone. The merge, in module order, makes the answer independent of how
// many threads walked.
#include "idr/Analysis/References.h"

#include "idr/IR/IdrDialect.h"
#include "idr/Support/Scc.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Threading.h"
#include "mlir/Interfaces/CallInterfaces.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/Sequence.h"

using namespace mlir;

namespace {

// What the walk of one body finds.
struct BodySlot {
  SmallVector<idr::References::Site> sites;
  // The positions of the functions the body names, each once, in the order
  // the walk first meets them: the edges of the graph.
  SmallVector<unsigned> targets;
  int64_t ops = 0;
  bool hasCall = false;
};

void walkBody(idr::FuncOp fn, mlir::SymbolTable &symbols,
              const llvm::DenseMap<Operation *, unsigned> &positions, BodySlot &slot) {
  llvm::SmallDenseSet<unsigned, 8> seen;
  fn.getBody().walk([&](Operation *op) {
    ++slot.ops;
    slot.hasCall |= isa<CallOpInterface>(op);
    idr::walkStoredAttributes(op, [&](Attribute nested) {
      auto ref = dyn_cast<FlatSymbolRefAttr>(nested);
      auto target = ref ? symbols.lookup<idr::FuncOp>(ref.getAttr()) : idr::FuncOp();
      if (!target)
        return;
      slot.sites.push_back({target, op});
      unsigned to = positions.lookup(target.getOperation());
      if (seen.insert(to).second)
        slot.targets.push_back(to);
    });
  });
}

} // namespace

idr::References::References(Operation *module, AnalysisManager &am) {
  mlir::SymbolTable &symbols = am.getAnalysis<mlir::SymbolTable>();
  for (FuncOp fn : cast<ModuleOp>(module).getOps<FuncOp>()) {
    positions.try_emplace(fn.getOperation(), static_cast<unsigned>(fns.size()));
    fns.push_back(fn);
  }
  unsigned n = static_cast<unsigned>(fns.size());
  SmallVector<BodySlot> slots(n);
  parallelForEach(module->getContext(), llvm::seq<size_t>(0, n),
                  [&](size_t at) { walkBody(fns[at], symbols, positions, slots[at]); });

  offsets.reserve(n + 1);
  sizes.reserve(n);
  calls.resize(n);
  recursive.resize(n);
  SmallVector<SmallVector<unsigned>> edges(n);
  for (unsigned at = 0; at < n; ++at) {
    BodySlot &slot = slots[at];
    offsets.push_back(static_cast<unsigned>(sites.size()));
    llvm::append_range(sites, slot.sites);
    sizes.push_back(slot.ops);
    if (slot.hasCall)
      calls.set(at);
    if (llvm::is_contained(slot.targets, at))
      recursive.set(at);
    edges[at] = std::move(slot.targets);
  }
  offsets.push_back(static_cast<unsigned>(sites.size()));
  for (const SmallVector<unsigned> &component : idr::components(edges)) {
    SmallVector<FuncOp> &members = parts.emplace_back();
    for (unsigned at : component) {
      members.push_back(fns[at]);
      if (component.size() > 1)
        recursive.set(at);
    }
  }
}

std::optional<unsigned> idr::References::position(FuncOp fn) const {
  auto found = positions.find(fn.getOperation());
  if (found == positions.end())
    return std::nullopt;
  return found->second;
}

ArrayRef<idr::References::Site> idr::References::of(FuncOp fn) const {
  std::optional<unsigned> at = position(fn);
  if (!at)
    return {};
  return ArrayRef<Site>(sites).slice(offsets[*at], offsets[*at + 1] - offsets[*at]);
}

bool idr::References::hasCall(FuncOp fn) const {
  std::optional<unsigned> at = position(fn);
  return at && calls.test(*at);
}

int64_t idr::References::ops(FuncOp fn) const {
  std::optional<unsigned> at = position(fn);
  return at ? sizes[*at] : 0;
}

bool idr::References::isRecursive(FuncOp fn) const {
  std::optional<unsigned> at = position(fn);
  return at && recursive.test(*at);
}

void idr::walkStoredAttributes(Operation *op, function_ref<void(Attribute)> visit) {
  auto each = [&](Attribute nested) { visit(nested); };
  op->getRawDictionaryAttrs().walk(each);
  if (!op->getPropertiesStorageSize())
    return;
  for (StringAttr name : op->getName().getAttributeNames())
    if (std::optional<Attribute> attr = op->getInherentAttr(name.getValue()); attr && *attr)
      attr->walk(each);
}
