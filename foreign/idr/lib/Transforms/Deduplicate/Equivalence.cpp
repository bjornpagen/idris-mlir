// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// When two idr.funcs are one function twice over: the same facts, and
// bodies whose ops, operands, types, attributes and regions match in order,
// locations aside. Each is read through the renames of the classes found
// before it, so callers that differ only in which copy they name are one
// function; that is what makes idr-deduplicate's merging transitive before
// it renames anything.
//
// A reference to the function itself is read as the other function's name.
// One that calls itself where the other calls the first is then one with
// it: the first is the fixpoint of its body, and the other is that body
// applied to the first, the same function.
//
// The facts are every attribute of the function but its name and
// `instance`. The name is what differs; `instance` is where the function
// came from, which no pass reads, and two copies of one function from two
// definitions are one function. Every other attribute (the type, the
// quantities in it, the arguments' and results' attributes, `total`,
// `effects`) is something a merge must not lose, so it must be the same.

#include "idr/Transforms/Deduplicate.h"

#include "mlir/IR/AttrTypeSubElements.h"
#include "mlir/IR/BuiltinAttributes.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace {

using Renames = idr::DataRemap::Renames;

// A function's attributes as a comparison reads them: a reference to the
// function itself as `as`, a reference to a function merged before as the
// one kept of its class, and a data type as it is: its labels are renamed
// by a remap of the whole program, never by a reading.
class Reading {
public:
  Reading(StringAttr self, StringAttr as, const Renames &renames) {
    replacer.addReplacement([](idr::DataType data) -> std::pair<Type, WalkResult> {
      return {data, WalkResult::skip()};
    });
    replacer.addReplacement([self, as, &renames](SymbolRefAttr ref) -> std::pair<Attribute, WalkResult> {
      StringAttr root = ref.getRootReference();
      StringAttr read = root == self ? as : renames.lookup(root);
      if (!read)
        return {ref, WalkResult::skip()};
      return {SymbolRefAttr::get(read, ref.getNestedReferences()), WalkResult::skip()};
    });
  }

  Attribute operator()(Attribute attr) { return attr ? replacer.replace(attr) : attr; }

private:
  AttrTypeReplacer replacer;
};

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
  explicit BodyHash(Reading &read) : read(read) {}

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
    hash = llvm::hash_combine(hash, read(op.getAttrDictionary()),
                              read(op.getPropertiesAsAttribute()));
    // A successor's operands are among the operands hashed above; which of
    // them go to which successor is an attribute of the op.
    for (Block *successor : op.getSuccessors())
      hash = llvm::hash_combine(hash, blocks.at(successor));
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

  Reading &read;
  // llvm::hash_code's default leaves its value unset: every hash starts
  // from the same seed, so that copies hash alike.
  llvm::hash_code hash = 0;
  DenseMap<Value, unsigned> values;
  DenseMap<Block *, unsigned> blocks;
  unsigned nextValue = 0;
  unsigned nextBlock = 0;
};

//===----------------------------------------------------------------------===//
// The comparison: two bodies, value by value, block by block
//===----------------------------------------------------------------------===//

struct BodyEqual {
  BodyEqual(Reading &lhsRead, Reading &rhsRead) : lhsRead(lhsRead), rhsRead(rhsRead) {}

  bool sameAttrs(Operation *lhs, Operation *rhs) {
    return lhsRead(lhs->getAttrDictionary()) == rhsRead(rhs->getAttrDictionary()) &&
           lhsRead(lhs->getPropertiesAsAttribute()) == rhsRead(rhs->getPropertiesAsAttribute());
  }

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
    if (!sameAttrs(lhs, rhs))
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

  Reading &lhsRead, &rhsRead;
  DenseMap<Value, Value> values;
  DenseMap<Block *, Block *> blocks;
};

} // namespace

namespace idr::deduplicate {

llvm::hash_code hashFunction(FuncOp fn, const Renames &renames) {
  // Every function's own name reads alike here, so copies hash alike.
  Reading read(fn.getSymNameAttr(), StringAttr::get(fn.getContext()), renames);
  llvm::hash_code hash = 0;
  for (NamedAttribute fact : factsOf(fn))
    hash = llvm::hash_combine(hash, fact.getName(), read(fact.getValue()));
  BodyHash body(read);
  body.region(fn.getBody());
  return llvm::hash_combine(hash, body.hash);
}

bool sameFunction(FuncOp lhs, FuncOp rhs, const Renames &renames) {
  StringAttr lhsSelf = lhs.getSymNameAttr();
  Reading lhsRead(lhsSelf, lhsSelf, renames);
  Reading rhsRead(rhs.getSymNameAttr(), lhsSelf, renames);
  SmallVector<NamedAttribute> lhsFacts = factsOf(lhs);
  SmallVector<NamedAttribute> rhsFacts = factsOf(rhs);
  if (lhsFacts.size() != rhsFacts.size() ||
      !llvm::all_of_zip(lhsFacts, rhsFacts, [&](NamedAttribute l, NamedAttribute r) {
        return l.getName() == r.getName() && lhsRead(l.getValue()) == rhsRead(r.getValue());
      }))
    return false;
  BodyEqual body(lhsRead, rhsRead);
  return body.region(lhs.getBody(), rhs.getBody());
}

} // namespace idr::deduplicate
