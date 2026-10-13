// quantities-kept: no pass drops or widens a quantity Idris proved. A
// quantity is a type's (quantityOf), one or many; a parameter, a field a
// match binds or a constructor field the emitted module declared keeps the
// quantity it had there. A binder is known by its location, what Emit
// gave it (the span of its Idris binder) or what the parser gave a module
// written by hand (the position of its name), with the names around it
// removed: passes copy locations with what they copy, so a binder that was
// renamed, cloned or moved is still found, and one made by inlining
// carries another location, which no binder of the emitted module has.

#include "idr/Transforms/Expect.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Location.h"
#include "mlir/Parser/Parser.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/StringMap.h"
#include "llvm/Support/ErrorHandling.h"

#include <optional>

using namespace mlir;

namespace idr::expect {

namespace {

constexpr StringRef property = "quantities-kept";

// The key of a binder at `loc`: the location under every name; none for
// an unknown location, which many binders share.
std::optional<Attribute> keyOf(Location loc) {
  while (auto named = dyn_cast<NameLoc>(loc))
    loc = named.getChildLoc();
  if (isa<UnknownLoc>(loc))
    return std::nullopt;
  LocationAttr key = loc;
  return key;
}

// Whether `block`'s arguments are binders Idris proved quantities of: a
// function's parameters, and the fields a match's region binds (its
// default region's scrutinee too). A loop's iteration state is the pass's.
bool bindsProved(Block &block) {
  Operation *parent = block.getParentOp();
  if (auto fn = dyn_cast<FuncOp>(parent))
    return &block == &fn.getBody().front();
  return isa<MatchOp, MatchLitOp>(parent);
}

// The quantity of `arg`, a binder: a parameter's from its function's
// signature, a bound field's from its type.
Quantity quantityOfBinder(BlockArgument arg) {
  if (auto fn = dyn_cast<FuncOp>(arg.getOwner()->getParentOp()))
    return quantityOf(fn.getArgumentTypes()[arg.getArgNumber()]);
  return quantityOf(arg.getType());
}

StringRef spelled(Quantity q) {
  switch (q) {
  case Quantity::One:
    return "1";
  case Quantity::Many:
    return "w";
  }
  llvm_unreachable("a quantity is one or many");
}

std::string ctorName(CtorOp ctor) {
  return (ctor->getParentOfType<DataOp>().getSymName() + "::@" + ctor.getSymName()).str();
}

SmallVector<Quantity> fieldQuantities(CtorOp ctor) {
  SmallVector<Quantity> out;
  for (Type type : ctor.getFieldTypes().getAsValueRange<TypeAttr>())
    out.push_back(quantityOf(type));
  return out;
}

} // namespace

LogicalResult quantitiesKept(ModuleOp module, AnalysisManager &, StringRef emitted) {
  if (emitted.empty())
    return fail(module.getLoc(), property) << "name the emitted module, as quantities-kept=<file>";
  OwningOpRef<ModuleOp> reference = parseSourceFile<ModuleOp>(emitted, module.getContext());
  if (!reference)
    return fail(module.getLoc(), property) << "cannot read " << emitted;

  // A key the emitted module gives two quantities says nothing of either
  // binder, and is dropped.
  llvm::DenseMap<Attribute, std::optional<Quantity>> proved;
  reference->walk([&](Block *block) {
    if (!bindsProved(*block))
      return;
    for (BlockArgument arg : block->getArguments()) {
      std::optional<Attribute> key = keyOf(arg.getLoc());
      if (!key)
        continue;
      Quantity q = quantityOfBinder(arg);
      auto [at, fresh] = proved.try_emplace(*key, q);
      if (!fresh && at->second != q)
        at->second = std::nullopt;
    }
  });
  llvm::StringMap<SmallVector<Quantity>> fields;
  reference->walk([&](CtorOp ctor) { fields[ctorName(ctor)] = fieldQuantities(ctor); });

  bool held = true;
  module.walk([&](Block *block) {
    if (!bindsProved(*block))
      return;
    Operation *parent = block->getParentOp();
    auto fn = dyn_cast<FuncOp>(parent);
    if (!fn)
      fn = parent->getParentOfType<FuncOp>();
    for (BlockArgument arg : block->getArguments()) {
      std::optional<Attribute> key = keyOf(arg.getLoc());
      auto was = key ? proved.find(*key) : proved.end();
      if (was == proved.end() || !was->second)
        continue;
      Quantity now = quantityOfBinder(arg);
      if (*was->second == now)
        continue;
      fail(arg.getLoc(), property) << (parent == fn ? "parameter " : "bound field ")
                                   << arg.getArgNumber() << " of " << where(parent)
                                   << " has quantity " << spelled(now) << ", and Idris proved "
                                   << spelled(*was->second);
      held = false;
    }
  });
  module.walk([&](CtorOp ctor) {
    std::string name = ctorName(ctor);
    auto was = fields.find(name);
    if (was == fields.end() || was->second == fieldQuantities(ctor))
      return;
    fail(ctor.getLoc(), property) << "the fields of @" << name << " have other quantities than Idris proved";
    held = false;
  });
  return success(held);
}

} // namespace idr::expect
