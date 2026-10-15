// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// lowered and in-llvm: what idr-lower, and then the conversion to LLVM,
// leave of a program, stated as what is gone and not as the ops that
// replace it. The idr dialect has no runtime form, linearity, the world
// and the facts of a function included, so after idr-lower nothing of it
// is in the program: no op, no type of a value, a parameter or a result,
// and no attribute, inside another or not. A fact of an idr.func that a
// lowered op kept under the same name would be one LLVM never reads, so
// it counts too. The program itself, which idr-lower leaves holding the
// lowered functions until idr-entry takes them out, is their container
// and is not asked.

#include "idr/Transforms/Expect.h"

#include "idr/IR/IdrDialect.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "llvm/ADT/StringSet.h"

using namespace mlir;

namespace idr::expect {

namespace {

bool ofIdr(Dialect &dialect) { return isa<IdrDialect>(dialect); }

// Whether `type` is the idr dialect's or holds a type or an attribute of
// it.
bool holdsIdr(Type type) {
  bool found = ofIdr(type.getDialect());
  type.walk([&](Type sub) { found |= ofIdr(sub.getDialect()); },
            [&](Attribute sub) { found |= ofIdr(sub.getDialect()); });
  return found;
}

bool holdsIdr(Attribute attr) {
  bool found = ofIdr(attr.getDialect());
  attr.walk([&](Type sub) { found |= ofIdr(sub.getDialect()); },
            [&](Attribute sub) { found |= ofIdr(sub.getDialect()); });
  return found;
}

// What of the idr dialect `op` holds, or nothing.
std::optional<std::string> leftIn(Operation *op, const llvm::StringSet<> &facts) {
  if (isa_and_nonnull<IdrDialect>(op->getDialect()))
    return (op->getName().getStringRef() + " is left").str();
  for (Type type : op->getResultTypes())
    if (holdsIdr(type))
      return (op->getName().getStringRef() + " gives a value of the idr dialect").str();
  for (Region &region : op->getRegions())
    for (Block &block : region)
      for (BlockArgument arg : block.getArguments())
        if (holdsIdr(arg.getType()))
          return (op->getName().getStringRef() + " binds a value of the idr dialect").str();
  if (auto fn = dyn_cast<FunctionOpInterface>(op); fn && holdsIdr(fn.getFunctionType()))
    return std::string("the signature holds a type of the idr dialect");
  for (NamedAttribute attr : op->getDiscardableAttrs()) {
    if (facts.contains(attr.getName().getValue()))
      return (op->getName().getStringRef() + " keeps the fact " + attr.getName().getValue() +
              " of an idr.func")
          .str();
    if (holdsIdr(attr.getValue()))
      return (op->getName().getStringRef() + " holds the attribute " + attr.getName().getValue() +
              " of the idr dialect")
          .str();
  }
  if (Attribute inherent = op->getPropertiesAsAttribute(); inherent && holdsIdr(inherent))
    return (op->getName().getStringRef() + " holds an attribute of the idr dialect").str();
  return std::nullopt;
}

} // namespace

// Anywhere or in @f, nothing of the idr dialect is left: no op, no type
// of a value, a block argument or a signature, no attribute of it, and no
// attribute named for a fact an idr.func holds.
LogicalResult lowered(ModuleOp module, AnalysisManager &, StringRef function) {
  constexpr StringRef property = "lowered";
  SmallVector<Operation *> roots;
  if (function.empty()) {
    for (Operation &op : programOf(module)->getRegion(0).getOps())
      roots.push_back(&op);
  } else {
    roots = rootsOf(module, function, property);
    if (roots.empty())
      return failure();
  }
  llvm::StringSet<> facts;
  for (StringRef name : FuncOp::getAttributeNames())
    facts.insert(name);
  bool held = true;
  for (Operation *root : roots)
    root->walk([&](Operation *op) {
      if (std::optional<std::string> found = leftIn(op, facts)) {
        fail(op->getLoc(), property) << *found << " in " << where(op);
        held = false;
      }
    });
  return success(held);
}

// Every op of the program is the LLVM dialect's: no cast between the
// dialects, no function or loop of another, is left. One error is given
// for each kind of op left.
LogicalResult inLLVM(ModuleOp module, AnalysisManager &, StringRef) {
  constexpr StringRef property = "in-llvm";
  Operation *program = programOf(module);
  llvm::StringSet<> reported;
  bool held = true;
  program->walk([&](Operation *op) {
    if (op == program || isa_and_nonnull<LLVM::LLVMDialect>(op->getDialect()))
      return;
    held = false;
    if (reported.insert(op->getName().getStringRef()).second)
      fail(op->getLoc(), property) << op->getName() << " is left in " << where(op);
  });
  return success(held);
}

} // namespace idr::expect
