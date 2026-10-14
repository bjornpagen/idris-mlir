// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The references of every function, from one walk of each body. A
// reference is what the body names that may run while it runs: the callee
// of an idr.call, the label of an idr.closure or an idr.suspend, the label
// of a closure constant, and the label of a constructor of a sum of
// closures, made by idr.con or held in a constant. That last is how a body
// makes a closure once idr-defunctionalize has turned closures into data,
// so it is a reference as the closure was. An idr.apply calls something and
// names no function, so it is not one.
//
// The bodies separate, so each is walked on a worker into its own slot:
// a worker reads its own body and the symbol table and writes its slot
// alone. The merge, in module order, makes the answer independent of how
// many threads walked.
#include "idr/Analysis/References.h"

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"
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
  bool callsUnknown = false;
};

void walkBody(idr::FuncOp fn, mlir::SymbolTable &symbols,
              const llvm::DenseMap<Operation *, unsigned> &positions, BodySlot &slot) {
  if (fn.isExternal())
    return;
  llvm::SmallDenseSet<unsigned, 8> seen;
  auto name = [&](Operation *at, StringAttr symbol) {
    auto target = symbols.lookup<idr::FuncOp>(symbol);
    if (!target) {
      slot.callsUnknown = true;
      return;
    }
    slot.sites.push_back({target, at});
    unsigned to = positions.lookup(target.getOperation());
    if (seen.insert(to).second)
      slot.targets.push_back(to);
  };
  auto label = [&](Operation *at, SymbolRefAttr ctor) {
    if (StringAttr named = idr::closureLabel(symbols, ctor))
      name(at, named);
  };
  fn.getBody().walk([&](Operation *op) {
    ++slot.ops;
    bool isCall = isa<CallOpInterface>(op);
    slot.hasCall |= isCall;
    if (auto call = dyn_cast<idr::CallOp>(op))
      name(op, call.getCalleeAttr().getAttr());
    else if (auto closure = dyn_cast<idr::ClosureOp>(op))
      name(op, closure.getCalleeAttr().getAttr());
    else if (auto suspend = dyn_cast<idr::SuspendOp>(op))
      name(op, suspend.getCalleeAttr().getAttr());
    else if (auto con = dyn_cast<idr::ConOp>(op))
      label(op, con.getCtor());
    else if (isCall && !isa<idr::ApplyOp>(op))
      slot.callsUnknown = true;
    idr::walkStoredAttributes(op, [&](Attribute nested) {
      if (auto closure = dyn_cast<idr::ClosureAttr>(nested))
        name(op, closure.getCallee().getAttr());
      else if (auto con = dyn_cast<idr::ConAttr>(nested))
        label(op, con.getCtor());
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
  unknown.resize(n);
  recursive.resize(n);
  SmallVector<SmallVector<unsigned>> edges(n);
  for (unsigned at = 0; at < n; ++at) {
    BodySlot &slot = slots[at];
    offsets.push_back(static_cast<unsigned>(sites.size()));
    llvm::append_range(sites, slot.sites);
    sizes.push_back(slot.ops);
    if (slot.hasCall)
      calls.set(at);
    if (slot.callsUnknown)
      unknown.set(at);
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

bool idr::References::callsUnknown(FuncOp fn) const {
  std::optional<unsigned> at = position(fn);
  return at && unknown.test(*at);
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

StringAttr idr::closureLabel(mlir::SymbolTable &symbols, SymbolRefAttr ctor) {
  auto data = symbols.lookup<DataOp>(ctor.getRootReference());
  if (!data)
    return {};
  if (data.getClosures())
    return ctor.getLeafReference();
  // A memo sum is the suspension as a closure sum is the closure: its label
  // constructors, which `labels` names, are its functions; its two states
  // are not, and `labels` does not name them.
  if (isMemo(data) && data.getLabelsAttr())
    for (auto label : data.getLabelsAttr().getAsRange<FlatSymbolRefAttr>())
      if (label.getAttr() == ctor.getLeafReference())
        return ctor.getLeafReference();
  return {};
}
