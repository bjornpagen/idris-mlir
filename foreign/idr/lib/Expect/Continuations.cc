// contified: every continuation became part of the function it continues.
// A private function whose one use is a call from another function is a
// continuation of that function (a case block of Idris's, usually), and
// idr-contify inlines it there; which functions it was is the passes'
// business, that none is left is the property.

#include "Expect/Expect.h"

#include "mlir/IR/SymbolTable.h"

#include "llvm/ADT/MapVector.h"

using namespace mlir;

namespace idr::expect {

LogicalResult contified(ModuleOp module, StringRef) noexcept {
  llvm::MapVector<Attribute, SmallVector<Operation *, 1>> users;
  if (std::optional<SymbolTable::UseRange> uses = SymbolTable::getSymbolUses(module.getBodyRegion()))
    for (const SymbolTable::SymbolUse &use : *uses)
      users[use.getSymbolRef().getRootReference()].push_back(use.getUser());
  bool held = true;
  for (auto fn : module.getOps<func::FuncOp>()) {
    if (fn.isPublic() || fn.isExternal())
      continue;
    auto found = users.find(fn.getSymNameAttr());
    if (found == users.end() || found->second.size() != 1)
      continue;
    auto call = dyn_cast<func::CallOp>(found->second.front());
    if (!call || call->getParentOfType<func::FuncOp>() == fn)
      continue;
    fail(call.getLoc(), "contified") << "@" << fn.getSymName() << " is called once, from "
                                      << where(call) << ", and is still a function";
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
