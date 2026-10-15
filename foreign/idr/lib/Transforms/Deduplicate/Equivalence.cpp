// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// When two idr.funcs are one function twice over: the same facts, and
// bodies whose ops, operands, types, attributes and regions match in order,
// locations aside, a reference to the function itself counting as the same
// in each. A reference to any other function must name the same one in
// both: idr-deduplicate renames those to the one kept of their class before
// it compares their callers, which is what makes its merging transitive.
//
// The facts are every attribute of the function but its name and
// `instance`. The name is what differs; `instance` is where the function
// came from, which no pass reads, and two copies of one function from two
// definitions are one function. Every other attribute (the type, the
// quantities in it, the arguments' and results' attributes, `total`,
// `effects`) is something a merge must not lose, so it must be the same.

#include "idr/Transforms/Deduplicate.h"

#include "mlir/IR/BuiltinAttributes.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace {

//===----------------------------------------------------------------------===//
// Attributes, a reference to the function itself counting as one reference
//===----------------------------------------------------------------------===//

// The hash of `attr` as the comparison below compares it: inside arrays and
// dictionaries piece by piece, so that a symbol reference is met on its
// own; anything else by its uniqued value, in which a reference no array or
// dictionary holds still names its function, and two copies whose only
// difference is such a self reference are simply not found.
llvm::hash_code hashAttr(Attribute attr, StringAttr self) {
  if (!attr)
    return llvm::hash_code{};
  if (auto ref = dyn_cast<SymbolRefAttr>(attr)) {
    if (ref.getRootReference() != self)
      return hash_value(attr);
    llvm::hash_code hash = llvm::hash_value(StringRef("idr.self"));
    for (FlatSymbolRefAttr nested : ref.getNestedReferences())
      hash = llvm::hash_combine(hash, nested.getAttr());
    return hash;
  }
  if (auto array = dyn_cast<ArrayAttr>(attr)) {
    llvm::hash_code hash = llvm::hash_combine(array.size());
    for (Attribute element : array)
      hash = llvm::hash_combine(hash, hashAttr(element, self));
    return hash;
  }
  if (auto dict = dyn_cast<DictionaryAttr>(attr)) {
    llvm::hash_code hash = llvm::hash_combine(dict.size());
    for (NamedAttribute element : dict)
      hash = llvm::hash_combine(hash, element.getName(), hashAttr(element.getValue(), self));
    return hash;
  }
  return hash_value(attr);
}

// Whether `lhs`, read in a function named `lhsSelf`, and `rhs`, in one named
// `rhsSelf`, say the same thing.
bool sameAttr(Attribute lhs, StringAttr lhsSelf, Attribute rhs, StringAttr rhsSelf) {
  if (!lhs || !rhs)
    return lhs == rhs;
  auto lhsRef = dyn_cast<SymbolRefAttr>(lhs);
  auto rhsRef = dyn_cast<SymbolRefAttr>(rhs);
  if (lhsRef || rhsRef) {
    if (!lhsRef || !rhsRef)
      return false;
    if (lhsRef.getRootReference() == lhsSelf && rhsRef.getRootReference() == rhsSelf)
      return lhsRef.getNestedReferences() == rhsRef.getNestedReferences();
    return lhs == rhs;
  }
  if (auto lhsArray = dyn_cast<ArrayAttr>(lhs)) {
    auto rhsArray = dyn_cast<ArrayAttr>(rhs);
    return rhsArray && lhsArray.size() == rhsArray.size() &&
           llvm::all_of_zip(lhsArray, rhsArray, [&](Attribute l, Attribute r) {
             return sameAttr(l, lhsSelf, r, rhsSelf);
           });
  }
  if (auto lhsDict = dyn_cast<DictionaryAttr>(lhs)) {
    auto rhsDict = dyn_cast<DictionaryAttr>(rhs);
    return rhsDict && lhsDict.size() == rhsDict.size() &&
           llvm::all_of_zip(lhsDict, rhsDict, [&](NamedAttribute l, NamedAttribute r) {
             return l.getName() == r.getName() && sameAttr(l.getValue(), lhsSelf, r.getValue(), rhsSelf);
           });
  }
  return lhs == rhs;
}

// The attributes of an op the comparison reads: its dictionary and its
// properties, which between them hold every inherent attribute (a call's
// callee, a constructor's name) and every discardable one.
bool sameAttrs(Operation *lhs, StringAttr lhsSelf, Operation *rhs, StringAttr rhsSelf) {
  return sameAttr(lhs->getAttrDictionary(), lhsSelf, rhs->getAttrDictionary(), rhsSelf) &&
         sameAttr(lhs->getPropertiesAsAttribute(), lhsSelf, rhs->getPropertiesAsAttribute(), rhsSelf);
}

// A function's facts: its attributes but its name and where it came from,
// in the dictionary's sorted order.
SmallVector<NamedAttribute> factsOf(idr::FuncOp fn) {
  StringAttr name = fn.getSymNameAttrName();
  StringAttr instance = fn.getInstanceAttrName();
  SmallVector<NamedAttribute> facts;
  for (NamedAttribute attr : fn->getAttrDictionary())
    if (attr.getName() != name && attr.getName() != instance)
      facts.push_back(attr);
  return facts;
}

//===----------------------------------------------------------------------===//
// The hash: a body's shape, values and blocks by the order they are met
//===----------------------------------------------------------------------===//

struct BodyHash {
  explicit BodyHash(StringAttr self) : self(self) {}

  unsigned value(Value v) {
    auto [found, inserted] = values.try_emplace(v, nextValue);
    if (inserted)
      ++nextValue;
    return found->second;
  }

  void op(Operation &op) {
    hash = llvm::hash_combine(hash, op.getName().getStringRef(), op.getNumOperands(),
                              op.getNumResults());
    for (Value operand : op.getOperands())
      hash = llvm::hash_combine(hash, value(operand));
    for (Value result : op.getResults()) {
      hash = llvm::hash_combine(hash, result.getType());
      value(result);
    }
    hash = llvm::hash_combine(hash, hashAttr(op.getAttrDictionary(), self),
                              hashAttr(op.getPropertiesAsAttribute(), self));
    // A successor's operands are among the operands hashed above; which of
    // them go to which successor is an attribute of the op.
    for (Block *successor : op.getSuccessors())
      hash = llvm::hash_combine(hash, blocks.lookup(successor));
    for (Region &region : op.getRegions())
      this->region(region);
  }

  void region(Region &region) {
    hash = llvm::hash_combine(hash, region.getNumArguments());
    for (Block &block : region) {
      blocks.try_emplace(&block, nextBlock++);
      hash = llvm::hash_combine(hash, block.getNumArguments());
      for (BlockArgument arg : block.getArguments()) {
        hash = llvm::hash_combine(hash, arg.getType());
        value(arg);
      }
    }
    for (Block &block : region)
      for (Operation &op : block)
        this->op(op);
  }

  StringAttr self;
  llvm::hash_code hash;
  DenseMap<Value, unsigned> values;
  DenseMap<Block *, unsigned> blocks;
  unsigned nextValue = 0;
  unsigned nextBlock = 0;
};

//===----------------------------------------------------------------------===//
// The comparison: two bodies, value by value, block by block
//===----------------------------------------------------------------------===//

struct BodyEqual {
  BodyEqual(StringAttr lhsSelf, StringAttr rhsSelf) : lhsSelf(lhsSelf), rhsSelf(rhsSelf) {}

  bool op(Operation *lhs, Operation *rhs) {
    if (lhs->getName() != rhs->getName() || lhs->getNumOperands() != rhs->getNumOperands() ||
        lhs->getNumResults() != rhs->getNumResults() ||
        lhs->getNumSuccessors() != rhs->getNumSuccessors() ||
        lhs->getNumRegions() != rhs->getNumRegions())
      return false;
    for (auto [l, r] : llvm::zip(lhs->getOperands(), rhs->getOperands()))
      if (values.lookup(l) != r)
        return false;
    for (auto [l, r] : llvm::zip(lhs->getResults(), rhs->getResults())) {
      if (l.getType() != r.getType())
        return false;
      values[l] = r;
    }
    if (!sameAttrs(lhs, lhsSelf, rhs, rhsSelf))
      return false;
    for (auto [l, r] : llvm::zip(lhs->getSuccessors(), rhs->getSuccessors()))
      if (blocks.lookup(l) != r)
        return false;
    for (auto [l, r] : llvm::zip(lhs->getRegions(), rhs->getRegions()))
      if (!region(l, r))
        return false;
    return true;
  }

  bool region(Region &lhs, Region &rhs) {
    auto lhsBlock = lhs.begin(), rhsBlock = rhs.begin();
    for (; lhsBlock != lhs.end() && rhsBlock != rhs.end(); ++lhsBlock, ++rhsBlock) {
      if (lhsBlock->getNumArguments() != rhsBlock->getNumArguments())
        return false;
      blocks[&*lhsBlock] = &*rhsBlock;
      for (auto [l, r] : llvm::zip(lhsBlock->getArguments(), rhsBlock->getArguments())) {
        if (l.getType() != r.getType())
          return false;
        values[l] = r;
      }
    }
    if (lhsBlock != lhs.end() || rhsBlock != rhs.end())
      return false;
    for (auto [l, r] : llvm::zip(lhs.getBlocks(), rhs.getBlocks())) {
      auto lhsOp = l.begin(), rhsOp = r.begin();
      for (; lhsOp != l.end() && rhsOp != r.end(); ++lhsOp, ++rhsOp)
        if (!op(&*lhsOp, &*rhsOp))
          return false;
      if (lhsOp != l.end() || rhsOp != r.end())
        return false;
    }
    return true;
  }

  StringAttr lhsSelf, rhsSelf;
  DenseMap<Value, Value> values;
  DenseMap<Block *, Block *> blocks;
};

} // namespace

namespace idr::deduplicate {

llvm::hash_code hashFunction(FuncOp fn) {
  StringAttr self = fn.getSymNameAttr();
  llvm::hash_code hash;
  for (NamedAttribute fact : factsOf(fn))
    hash = llvm::hash_combine(hash, fact.getName(), hashAttr(fact.getValue(), self));
  BodyHash body(self);
  body.region(fn.getBody());
  return llvm::hash_combine(hash, body.hash);
}

bool sameFunction(FuncOp lhs, FuncOp rhs) {
  StringAttr lhsSelf = lhs.getSymNameAttr();
  StringAttr rhsSelf = rhs.getSymNameAttr();
  SmallVector<NamedAttribute> lhsFacts = factsOf(lhs);
  SmallVector<NamedAttribute> rhsFacts = factsOf(rhs);
  if (lhsFacts.size() != rhsFacts.size() ||
      !llvm::all_of_zip(lhsFacts, rhsFacts, [&](NamedAttribute l, NamedAttribute r) {
        return l.getName() == r.getName() && sameAttr(l.getValue(), lhsSelf, r.getValue(), rhsSelf);
      }))
    return false;
  BodyEqual body(lhsSelf, rhsSelf);
  return body.region(lhs.getBody(), rhs.getBody());
}

} // namespace idr::deduplicate
