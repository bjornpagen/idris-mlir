// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The contract quantities-kept: no pass drops or widens what Idris proved
// of a binder, checked by --idr-contracts after every pass.
// A binder's uses are its type's (usesOf), once or many; a parameter of a
// function (a lambda is one) keeps the uses it had in the emitted module,
// wherever a pass carries it. A binder is known by its identity, the
// `#idr.binder<definition, index>` Emit fuses into its location: typed,
// one per binder, so no two binders are confused and none is set aside.
// Of the binders a block binds, Emit gives one to parameters alone, so the
// check holds parameters: a field a case unpacks carries none, and neither
// does a binder a pass makes, whose uses are derived from its source's by
// the one derivation the passes that copy share. A constructor's fields
// are its family's declaration, whose uses no pass can change but by
// declaring another family.
//
// A location is discardable, so the check also holds that no pass loses an
// identity where the binder stays: a parameter used once of a function the
// program still has stands after every pass (linear-kept), so its identity
// is carried by some binder, and one no binder carries was lost. Where the
// binder may go with its identity, the identity's absence says nothing: a
// parameter used many times goes with its position when a pass drops it
// unused, a function's with the function, and a region's with the region
// (a join a pass dissolves); those are held where they are found.

#include "idr/Transforms/Expect.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Location.h"
#include "llvm/ADT/DenseSet.h"

using namespace mlir;

namespace idr::expect {

// The metadata of a fused location among the location's parts.
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

namespace {

// The function `arg` is a parameter of; null for a binder a region binds.
FuncOp functionOf(BlockArgument arg) { return dyn_cast<FuncOp>(arg.getOwner()->getParentOp()); }

// The uses of `arg`, a binder: a function parameter's from its function's
// signature, a parameter a pass carried into a region's from its type.
Uses usesOfBinder(BlockArgument arg) {
  if (FuncOp fn = functionOf(arg))
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
    Uses uses = usesOfBinder(arg);
    auto [at, fresh] = proved.uses.try_emplace(identity, uses);
    if (!fresh) {
      emitError(arg.getLoc()) << "two binders of the emitted module are " << identity;
      unique = false;
      return;
    }
    if (FuncOp fn = functionOf(arg); fn && uses == Uses::Once)
      proved.onceParameters.push_back({identity, fn.getSymNameAttr()});
  });
  if (!unique)
    return failure();
  return proved;
}

LogicalResult usesKept(const ProvedUses &proved, ModuleOp module, SymbolTable &symbols,
                       StringRef property) {
  bool held = true;
  llvm::DenseSet<BinderAttr> carried;
  forEachIdentified(module, [&](BinderAttr identity, BlockArgument arg) {
    carried.insert(identity);
    auto was = proved.uses.find(identity);
    // A pass copies an identity, never makes one, so every identity is one
    // of the emitted module's binders, unless what Idris proved of them
    // could not be read: then no binder is held to anything, and each says
    // so.
    if (was == proved.uses.end()) {
      fail(arg.getLoc(), property) << identity << " is no binder's of the emitted module";
      held = false;
      return;
    }
    Uses now = usesOfBinder(arg);
    if (now == was->second)
      return;
    fail(arg.getLoc(), property) << identity << " is " << stringifyUses(now)
                                 << ", and Idris proved it " << stringifyUses(was->second);
    held = false;
  });
  for (const OnceParameter &parameter : proved.onceParameters) {
    if (carried.contains(parameter.identity))
      continue;
    // A function the program no longer has took its parameters with it.
    auto fn = symbols.lookup<FuncOp>(parameter.function);
    if (!fn)
      continue;
    fail(fn.getLoc(), property) << "@" << parameter.function.getValue() << " keeps "
                                << parameter.identity
                                << ", which Idris proved used once, on no binder";
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
