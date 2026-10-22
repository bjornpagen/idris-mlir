// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The contract quantities-kept: no pass drops or widens what Idris proved
// of a binder, checked by --idr-contracts after every pass.
// A binder's uses are its type's (usesOf), once or many; a parameter of a
// function (a lambda is one) or a field a match binds keeps the uses it had
// in the emitted module. A binder is known by its identity, the
// `#idr.binder<definition, index>` Emit fuses into its location: typed,
// one per binder, so no two binders are confused and none is set aside. A
// binder a pass makes carries none, and so is held to nothing here: its
// uses are derived from its source's by the one derivation the passes
// that copy share. A constructor's fields are its family's declaration,
// whose uses no pass can change but by declaring another family.

#include "idr/Transforms/Expect.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Location.h"

using namespace mlir;

namespace idr::expect {

namespace {

// The identity a location carries: the metadata of a fused location among
// its parts, however the passes nested it in names, call sites and fusions.
std::optional<BinderAttr> identityOf(Location loc) {
  std::optional<BinderAttr> found;
  loc->walk([&](Location part) {
    if (auto fused = dyn_cast<FusedLoc>(part))
      if (auto binder = dyn_cast_or_null<BinderAttr>(fused.getMetadata())) {
        found = binder;
        return WalkResult::interrupt();
      }
    return WalkResult::advance();
  });
  return found;
}

// The uses of `arg`, a binder: a function parameter's from its function's
// signature, a bound field's from its type.
Uses usesOfBinder(BlockArgument arg) {
  if (auto fn = dyn_cast<FuncOp>(arg.getOwner()->getParentOp()))
    return usesOf(fn.getArgumentTypes()[arg.getArgNumber()]);
  return usesOf(arg.getType());
}

// Each binder of `module` that carries an identity, with it.
template <class Visit>
void forEachIdentified(ModuleOp module, Visit visit) {
  module->walk([&](Block *block) {
    for (BlockArgument arg : block->getArguments())
      if (std::optional<BinderAttr> identity = identityOf(arg.getLoc()))
        visit(*identity, arg);
  });
}

} // namespace

FailureOr<ProvedUses> provedUses(ModuleOp emitted) {
  ProvedUses proved;
  bool unique = true;
  forEachIdentified(emitted, [&](BinderAttr identity, BlockArgument arg) {
    auto [at, fresh] = proved.try_emplace(identity, usesOfBinder(arg));
    if (fresh)
      return;
    emitError(arg.getLoc()) << "two binders of the emitted module are " << identity;
    unique = false;
  });
  if (!unique)
    return failure();
  return proved;
}

LogicalResult usesKept(const ProvedUses &proved, ModuleOp module, StringRef property) {
  bool held = true;
  forEachIdentified(module, [&](BinderAttr identity, BlockArgument arg) {
    auto was = proved.find(identity);
    if (was == proved.end())
      return;
    Uses now = usesOfBinder(arg);
    if (now == was->second)
      return;
    fail(arg.getLoc(), property) << identity << " is " << stringifyUses(now)
                                 << ", and Idris proved it " << stringifyUses(was->second);
    held = false;
  });
  return success(held);
}

} // namespace idr::expect
