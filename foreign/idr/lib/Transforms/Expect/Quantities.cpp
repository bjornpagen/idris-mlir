// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// quantities-kept: no pass drops or widens a quantity Idris proved. A
// quantity is a type's (quantityOf), one or many; a parameter of a
// function or a lambda, a field a match binds or a constructor field the
// emitted module declared keeps the quantity it had there. A binder is
// known by its location: the name Emit gave it over the span of its
// Idris definition, or what the parser gave a module written by hand
// (the position of its name). The span alone is not the binder: every
// binder of one definition shares it, so the name over it is part of
// the key. Passes copy locations with what they copy, so a binder that
// was cloned or moved is still found; a binder a pass makes of its own
// (a clone's destination, at the function's location) or for a value
// that was no binder when emitted (a capture, at the value's location)
// carries a name no emitted binder at that span has, and one made by
// inlining carries another location outright.

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

// The key of a binder at `loc`: its outermost name over the location
// under every name; none where that location is unknown, which many
// binders share. A parser position (FileLineColLoc) names the text it
// was read from, and the module and the emitted module are different
// texts, so for one only its line and column are the binder's identity;
// a span Emit wrote (FileLineColRange) names its Idris source, which
// both sides share.
std::optional<Attribute> keyOf(Location loc) {
  StringAttr name;
  if (auto named = dyn_cast<NameLoc>(loc))
    name = named.getName();
  while (auto named = dyn_cast<NameLoc>(loc))
    loc = named.getChildLoc();
  if (isa<UnknownLoc>(loc))
    return std::nullopt;
  LocationAttr key = loc;
  if (auto at = dyn_cast<FileLineColLoc>(loc))
    key = FileLineColLoc::get(at.getContext(), "", at.getLine(), at.getColumn());
  if (name)
    return NameLoc::get(name, key);
  return key;
}

// Whether `block`'s arguments are binders Idris proved quantities of: a
// function's parameters, a lambda's parameters (isolation lifts them to
// a function's, so the emitted module must prove them under the same
// key), and the fields a match's region binds (its default region's
// scrutinee too). A loop's iteration state is the pass's.
bool bindsProved(Block &block) {
  Operation *parent = block.getParentOp();
  if (auto fn = dyn_cast<FuncOp>(parent))
    return &block == &fn.getBody().front();
  return isa<MatchOp, MatchLitOp, LambdaOp>(parent);
}

// The quantity of `arg`, a binder: a function parameter's from its
// function's signature, a lambda parameter's or a bound field's from
// its type.
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
    for (BlockArgument arg : block->getArguments()) {
      std::optional<Attribute> key = keyOf(arg.getLoc());
      auto was = key ? proved.find(*key) : proved.end();
      if (was == proved.end() || !was->second)
        continue;
      Quantity now = quantityOfBinder(arg);
      if (*was->second == now)
        continue;
      fail(arg.getLoc(), property) << (isa<MatchOp, MatchLitOp>(parent) ? "bound field " : "parameter ")
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
