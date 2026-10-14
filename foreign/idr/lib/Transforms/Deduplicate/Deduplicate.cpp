// idr-deduplicate: of each group of private idr.funcs with the same type,
// the same facts and bodies that match op for op, the first stays and every
// use of the others names it.
//
// Monomorphisation writes one function per instantiation, and what Idris
// erased is gone from some of them alike: PrimIO.fromPrim and PrimIO.toPrim
// at one type are both the identity on the action they are given, and a
// stage0 module holds some fifteen hundred such second copies. Each one is
// work for every later pass and code in the program. LLVM's MergeFunctions
// does this for llvm functions, by a hash and then a comparison; this pass
// is that shape on idr.func, where the facts a merge must not lose (total,
// effects, the quantities in the types) are in the comparison, and where
// MLIR's symbol user map rewrites the uses.
//
// Two bodies match when their ops, operands, types, attributes and regions
// match in order, locations aside, a symbol reference to the function
// itself counting as the same reference in each: two self-recursive copies
// are one function. A reference to any other function must name the same
// one in both, so a pair alike only once their callees are merged is left
// for a later run of the pass. The pass is its own fixpoint's first step:
// run it again and the callers of what it merged may merge in turn.
//
// What kind of use may be renamed is decided before anything is rewritten:
// a call's callee, a closure's or a suspension's label, and a constant
// naming the function. A declaration's `labels` fixes which constructor is
// which label, and a clone's key names the function it specializes; a
// function either names is left alone, as is a function used by an op of
// any other kind, and a group one of whose functions uses another.

#include "idr/Transforms/Deduplicate.h"

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/SymbolTable.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/Hashing.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallPtrSet.h"

namespace idr {
#define GEN_PASS_DEF_IDRDEDUPLICATE
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

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

// The hash of a function: the facts two copies must share, then the body.
// `no_inline` is not among them (the one kept takes the group's). The
// `instance` fact is: no pass reads it, but it is the function's
// provenance — an expect check names a function by the definition it is
// an instance of — and merging two instantiations of different
// definitions would erase one of the two names a check may look up.
llvm::hash_code hashFunc(idr::FuncOp fn) {
  BodyHash body(fn.getSymNameAttr());
  body.region(fn.getBody());
  return llvm::hash_combine(fn.getFunctionType(), fn.getTotal(), fn.getBreakLast(),
                            fn.getInstanceAttr(), fn.getEffectsAttr(), fn.getArgAttrsAttr(),
                            fn.getResAttrsAttr(), body.hash);
}

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

// Whether two functions are one function twice over: the facts hashFunc
// hashes, then the bodies.
bool sameFunc(idr::FuncOp lhs, idr::FuncOp rhs) {
  if (lhs.getFunctionType() != rhs.getFunctionType() || lhs.getTotal() != rhs.getTotal() ||
      lhs.getBreakLast() != rhs.getBreakLast() || lhs.getInstanceAttr() != rhs.getInstanceAttr() ||
      lhs.getEffectsAttr() != rhs.getEffectsAttr() ||
      lhs.getArgAttrsAttr() != rhs.getArgAttrsAttr() || lhs.getResAttrsAttr() != rhs.getResAttrsAttr())
    return false;
  BodyEqual body(lhs.getSymNameAttr(), rhs.getSymNameAttr());
  return body.region(lhs.getBody(), rhs.getBody());
}

//===----------------------------------------------------------------------===//
// Which functions may go, and the merge
//===----------------------------------------------------------------------===//

// The function a clone's key names, as idr-expect reads it.
StringAttr copiedFrom(idr::CloneAttr clone) {
  Attribute key = clone.getKey();
  if (auto spec = dyn_cast<idr::SpecKeyAttr>(key))
    return spec.getOrigin();
  if (auto apply = dyn_cast<idr::KeyApplyAttr>(key))
    return apply.getCallee();
  return cast<idr::KeyApplyFieldAttr>(key).getCallee();
}

// Whether every use of `fn` is one whose renaming states the same program:
// in its own body, or a call, a closure, a suspension or a constant naming
// it. A use by the function op itself (its clone fact) is the caller's to
// refuse, by the names clones and declarations hold.
bool renamable(idr::FuncOp fn, ArrayRef<Operation *> users) {
  for (Operation *user : users) {
    if (user->getParentOfType<idr::FuncOp>() == fn)
      continue;
    if (!isa<idr::CallOp, idr::ClosureOp, idr::SuspendOp, idr::ConstantOp>(user))
      return false;
  }
  return true;
}

struct Deduplicate : idr::impl::IdrDeduplicateBase<Deduplicate> {
  void runOnOperation() override {
    ModuleOp module = getOperation();
    SymbolTable &symbols = getAnalysis<SymbolTable>();
    SymbolTableCollection tables;
    SymbolUserMap users(tables, module);

    // The names no merge may take: a declaration's labels, whose order is
    // its constructors', and the functions clones are clones of, which the
    // clone table keys by. The user map may not list either use (a label is
    // an attribute of a declaration, a clone fact a property of a
    // function), so they are read where they are written.
    DenseSet<StringAttr> held;
    for (idr::DataOp data : module.getOps<idr::DataOp>())
      if (ArrayAttr labels = data.getLabelsAttr())
        for (FlatSymbolRefAttr label : labels.getAsRange<FlatSymbolRefAttr>())
          held.insert(label.getAttr());
    for (idr::FuncOp fn : module.getOps<idr::FuncOp>())
      if (idr::CloneAttr clone = fn.getCloneAttr()) {
        held.insert(clone.getFunction().getAttr());
        held.insert(copiedFrom(clone));
      }

    // The functions that may be a second copy of another, by their hash.
    // A function that is an instance of a definition is not among them:
    // its name is that definition's provenance, which a check looks a
    // function up by, and merging it into a twin would erase the name.
    // The mass of duplicates is in what elaboration made no definition
    // of (outlines of lambdas and case blocks), which carries no fact.
    DenseMap<size_t, SmallVector<idr::FuncOp>> buckets;
    for (idr::FuncOp fn : module.getOps<idr::FuncOp>()) {
      if (!fn.isPrivate() || fn.isExternal() || fn.getCloneAttr() || fn.getInstanceAttr() ||
          held.contains(fn.getSymNameAttr()) || !renamable(fn, users.getUsers(fn)))
        continue;
      buckets[static_cast<size_t>(hashFunc(fn))].push_back(fn);
    }

    // Each bucket's groups, a group being the functions the comparison
    // finds equal to its first. A group one of whose functions is used
    // from another's body is left whole: renaming that use would rewrite
    // the recursion between them into a recursion on the one kept, which
    // the comparison did not prove.
    struct Group {
      idr::FuncOp keep;
      SmallVector<idr::FuncOp> rest;
    };
    SmallVector<Group> groups;
    for (auto &bucket : buckets) {
      SmallVector<idr::FuncOp> &candidates = bucket.second;
      while (!candidates.empty()) {
        Group group;
        group.keep = candidates.front();
        SmallVector<idr::FuncOp> rest;
        for (idr::FuncOp fn : ArrayRef(candidates).drop_front())
          (sameFunc(group.keep, fn) ? group.rest : rest).push_back(fn);
        candidates = std::move(rest);
        if (group.rest.empty())
          continue;
        llvm::SmallPtrSet<Operation *, 4> members{group.keep};
        members.insert(group.rest.begin(), group.rest.end());
        bool crossed = llvm::any_of(members, [&](Operation *member) {
          return llvm::any_of(users.getUsers(member), [&](Operation *user) {
            auto caller = user->getParentOfType<idr::FuncOp>();
            return caller && caller != member && members.contains(caller);
          });
        });
        if (!crossed)
          groups.push_back(std::move(group));
      }
    }
    if (groups.empty())
      return markAllAnalysesPreserved();

    // The merges: every use renamed first, through the user map the
    // checks above read, and the second copies erased after. The map's
    // users are the uses there are to rename (a private function's uses
    // are all in the module, and the uses the map does not list -- a
    // declaration's labels, a clone's key -- refused their functions
    // above), and renaming through it touches each use once, where
    // SymbolTable::replaceAllSymbolUses walks the module for every
    // function erased. A use inside a function itself being erased is
    // renamed with the rest and goes with its body, which is why nothing
    // is erased until every rename is done.
    for (Group &group : groups) {
      bool noInline = group.keep.getNoInline() ||
                      llvm::any_of(group.rest, [](idr::FuncOp fn) { return fn.getNoInline(); });
      if (noInline != group.keep.getNoInline())
        group.keep.setNoInline(noInline);
      for (idr::FuncOp fn : group.rest)
        users.replaceAllUsesWith(fn, group.keep.getSymNameAttr());
      numMerged += group.rest.size();
      ++numGroups;
    }
    for (Group &group : groups)
      for (idr::FuncOp fn : group.rest)
        symbols.erase(fn);
    // Every function erased went through the table.
    markAnalysesPreserved<SymbolTable>();
  }
};

} // namespace

