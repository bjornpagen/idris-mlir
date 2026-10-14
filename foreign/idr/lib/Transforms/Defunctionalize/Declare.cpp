// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The sums declared for the converted keys, before the conversion that
// gives the slots their types.

#include "idr/IR/IdrDialect.h"
#include "idr/Analysis/Labels.h"
#include "idr/IR/Symbols.h"
#include "idr/Transforms/Defunctionalize.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/SymbolTable.h"

using namespace mlir;

namespace idr::defunctionalize {

// A sum of closures has a constructor per label, whose fields are its
// captures. A memo sum has one too, and then the states a force writes its
// cell into: `running` while a label runs, and `forced` with the value. Its
// `labels` names the label functions where the module resolves them:
// nothing else uses a label's function once its suspensions are
// constructors, and a function nothing uses is dead to every analysis. The
// sums' names were chosen when the keys were numbered, and the slots' types
// already name them, so a name the table would have to change is a sum the
// types would miss.
LogicalResult declareSums(ModuleOp module, const Slots &slots) {
  SymbolTable &symbols = slots.symbols();
  OpBuilder b(module.getContext());
  for (auto &[key, sum] : slots.keys())
    if (sum && symbols.lookup(getSumName(sum).getAttr()))
      return module.emitError("internal error: idr-defunctionalize: the sum @")
             << getSumName(sum).getValue() << " is already declared";
  Block::iterator at = module.getBody()->begin();
  for (auto &[key, sum] : slots.keys()) {
    if (!sum)
      continue;
    StringAttr name = getSumName(sum).getAttr();
    bool memo = Slots::isLazy(key);
    SmallVector<Attribute> labels;
    for (auto label : key.second.getAsRange<StringAttr>())
      labels.push_back(FlatSymbolRefAttr::get(label));
    auto data = DataOp::create(b, module.getLoc(), name,
                               isa<BoxType>(sum) ? b.getUnitAttr() : UnitAttr(),
                               memo ? UnitAttr() : b.getUnitAttr(),
                               memo ? b.getUnitAttr() : UnitAttr(),
                               memo ? b.getArrayAttr(labels) : ArrayAttr(), InstanceAttr());
    OpBuilder inner = OpBuilder::atBlockEnd(&data.getBody().emplaceBlock());
    for (auto label : key.second.getAsRange<StringAttr>()) {
      // The captures' types carry their quantities into the fields.
      Location loc = slots.labels().function(label).getLoc();
      CtorOp::create(inner, loc, label, b.getTypeArrayAttr(slots.captureTypes(label, key)),
                     UnitAttr());
    }
    if (memo) {
      CtorOp::create(inner, module.getLoc(), b.getStringAttr(memoRunning),
                     b.getTypeArrayAttr(TypeRange()), UnitAttr());
      CtorOp::create(inner, module.getLoc(), b.getStringAttr(memoForced),
                     b.getTypeArrayAttr({slots.forcedType(key)}), UnitAttr());
    }
    symbols.insert(data, at);
    at = std::next(Block::iterator(data));
  }
  return success();
}

} // namespace idr::defunctionalize
