// The module's closures and suspensions, gathered once for the analysis of
// their labels: the closure and suspension ops and constants of each label,
// the applies and the labels each may call, and the functions that escape.

#include "idr/Analysis/Labels.h"

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"

#include "mlir/IR/SymbolTable.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr {
namespace {

// Whether a closure is inside `attr`, each part answered once into `memo`:
// every part, a closure's captures too, so that a walk of the constant into
// its closures finds each part it meets answered.
bool holds(Attribute attr, llvm::DenseMap<Attribute, bool> &memo) {
  auto closure = dyn_cast<ClosureAttr>(attr);
  auto con = dyn_cast<ConAttr>(attr);
  if (!closure && !con)
    return false;
  if (auto it = memo.find(attr); it != memo.end())
    return it->second;
  bool found = static_cast<bool>(closure);
  if (closure)
    for (Attribute capture : closure.getCaptures())
      (void)holds(capture, memo);
  else
    eachField(con, [&](Attribute field, unsigned) { found = holds(field, memo) || found; });
  memo[attr] = found;
  return found;
}

} // namespace

Type Labels::fieldType(SymbolRefAttr ctor, unsigned index) const {
  CtorOp decl = lookupCtor(table, ctor);
  return decl ? decl.getFieldType(index) : Type();
}

bool Labels::holdsClosure(Attribute attr) const {
  if (auto it = closureFree.find(attr); it != closureFree.end())
    return it->second;
  // A part no constant of the module had: one a rewrite made.
  llvm::DenseMap<Attribute, bool> memo;
  return holds(attr, memo);
}

void Labels::closuresIn(Attribute attr, Type type,
                        function_ref<void(ClosureAttr, Type)> visit) const {
  if (!holdsClosure(attr))
    return;
  if (auto closure = dyn_cast<ClosureAttr>(attr)) {
    visit(closure, type);
    FuncOp fn = function(closure.getCallee().getAttr());
    for (auto [i, capture] : llvm::enumerate(closure.getCaptures()))
      if (fn && i < fn.getNumArguments())
        closuresIn(capture, fn.getArgumentTypes()[i], visit);
    return;
  }
  if (auto con = dyn_cast<ConAttr>(attr))
    eachField(con, [&](Attribute field, unsigned i) {
      if (Type declared = fieldType(con.getCtor(), i))
        closuresIn(field, declared, visit);
    });
}

void Labels::gather(Operation *module) {
  module->walk([&](Operation *inner) {
    if (auto closure = dyn_cast<ClosureOp>(inner)) {
      closureOps[closure.getCalleeAttr().getAttr()].push_back(closure);
    } else if (auto suspend = dyn_cast<SuspendOp>(inner)) {
      suspendOps[suspend.getCalleeAttr().getAttr()].push_back(suspend);
    } else if (auto apply = dyn_cast<ApplyOp>(inner)) {
      applyOps.push_back(apply);
    } else if (auto constant = dyn_cast<ConstantOp>(inner)) {
      holds(constant.getValue(), closureFree);
      closuresIn(constant.getValue(), constant.getType(), [&](ClosureAttr c, Type type) {
        auto &into = isLazyType(type) ? suspendConstants : constantClosures;
        into[c.getCallee().getAttr()].push_back(c.getCaptures());
      });
    }
  });

  // An apply may call a label whose signature ends in its callee's type:
  // the label takes its captures first, then the closure type's arguments.
  // Each label is filed once under every closure type it fits, for the
  // applies whose callee's labels are unknown: a known callee names the
  // labels itself, and its apply joins its arguments into their entries,
  // so no entry is ever joined from a scan of the applies that fit it by
  // type alone.
  if (!applyOps.empty()) {
    llvm::DenseSet<StringAttr> filed;
    auto file = [&](StringAttr label) {
      FuncOp fn = function(label);
      if (!fn || !filed.insert(label).second)
        return;
      ArrayRef<Type> inputs = fn.getArgumentTypes();
      for (size_t k = 0; k <= inputs.size(); ++k)
        byType[FnType::get(fn.getContext(), inputs.take_back(k), fn.getResultTypes())]
            .push_back(label);
    };
    for (auto &entry : closureOps)
      file(entry.first);
    for (auto &entry : constantClosures)
      file(entry.first);
  }

  if (std::optional<SymbolTable::UseRange> uses = SymbolTable::getSymbolUses(module))
    for (const SymbolTable::SymbolUse &use : *uses)
      // A clone names itself; no closure escapes there. A suspension names
      // its function the way a closure does.
      if (!isa<CallOp, FuncOp, ClosureOp, SuspendOp, ConstantOp, ConOp, FieldOp, MatchOp>(
              use.getUser()))
        escaping.insert(use.getSymbolRef().getRootReference());
}

} // namespace idr
