// constant-stack and counted-loop: what idr-tail-loops and idr-tail-calls
// guarantee of a function, stated as properties of the call graph and of the
// loops, not as the ops that happen to show them.

#include "Expect/Expect.h"

#include "mlir/Dialect/Linalg/IR/Linalg.h"
#include "mlir/Dialect/Linalg/Utils/Utils.h"
#include "mlir/Dialect/Vector/IR/VectorOps.h"
#include "mlir/Interfaces/CastInterfaces.h"

import idr.graph;

using namespace mlir;

namespace idr::expect {
namespace {

// A function's reference to another: by a call, guaranteed a tail call or
// not, or by a closure or an address that names it.
struct Reference {
  Operation *target;
  bool tailCall;
};

// The functions the body of `fn`, a function, refers to. What the
// function's own attributes name (the clone it is) is provenance, not a
// call.
SmallVector<Reference> references(Operation *fn, SymbolTable &symbols) {
  SmallVector<Reference> out;
  Region &body = cast<FunctionOpInterface>(fn).getFunctionBody();
  if (std::optional<SymbolTable::UseRange> uses = SymbolTable::getSymbolUses(&body))
    for (const SymbolTable::SymbolUse &use : *uses) {
      Operation *target = symbols.lookup(use.getSymbolRef().getRootReference());
      if (!isa_and_nonnull<FunctionOpInterface>(target))
        continue;
      auto call = dyn_cast<LLVM::CallOp>(use.getUser());
      out.push_back(
          {target, call && call.getTailCallKind() == LLVM::tailcallkind::TailCallKind::MustTail});
    }
  return out;
}

} // namespace

// No recursion reachable from the function grows the stack: each function it
// may call, itself included, that is on a cycle of references refers to the
// others of its cycle only by guaranteed tail calls, each of which replaces
// its caller's frame. Functions without a body in the module call nothing
// back.
LogicalResult constantStack(ModuleOp module, StringRef function) {
  constexpr StringRef property = "constant-stack";
  SmallVector<Operation *> reached =
      llvm::map_to_vector(namedFunctions(module, function, property),
                          [](FunctionOpInterface fn) { return fn.getOperation(); });
  if (reached.empty())
    return failure();
  SymbolTable symbols(module);
  llvm::DenseSet<Operation *> seen(reached.begin(), reached.end());
  for (size_t next = 0; next < reached.size(); ++next)
    for (Reference ref : references(reached[next], symbols))
      if (seen.insert(ref.target).second)
        reached.push_back(ref.target);
  auto refers = [&](Operation *fn) {
    return llvm::map_to_vector(references(fn, symbols), [](Reference ref) { return ref.target; });
  };
  bool held = true;
  for (const SmallVector<Operation *> &cycle :
       idr::graph::stronglyConnected<Operation *>(reached, refers)) {
    llvm::DenseSet<Operation *> members(cycle.begin(), cycle.end());
    bool grows = false;
    for (Operation *fn : cycle)
      for (Reference ref : references(fn, symbols))
        grows |= members.contains(ref.target) && !ref.tailCall;
    if (!grows)
      continue;
    InFlightDiagnostic error = fail(cycle.front()->getLoc(), property)
                               << "the stack grows with the recursion of";
    for (Operation *fn : cycle)
      error << " @" << SymbolTable::getSymbolName(fn).getValue();
    held = false;
  }
  return success(held);
}

// The function (or a clone of it) loops, and every loop it has counts to a
// bound with a step: an scf.for, which says its trip count, and no
// scf.while.
LogicalResult countedLoop(ModuleOp module, StringRef function) {
  constexpr StringRef property = "counted-loop";
  SmallVector<func::FuncOp> functions = named(module, function, property);
  if (functions.empty())
    return failure();
  unsigned counted = 0;
  bool held = true;
  for (func::FuncOp fn : functions)
    fn.walk([&](Operation *op) {
      if (isa<scf::ForOp>(op))
        ++counted;
      if (isa<scf::WhileOp>(op)) {
        fail(op->getLoc(), property) << "a loop of " << where(op) << " has no trip count";
        held = false;
      }
    });
  if (held && counted == 0) {
    fail(functions.front().getLoc(), property) << function << " has no loop";
    held = false;
  }
  return success(held);
}

// The body of a loop over an array runs once per element as one linalg
// operation after lowering, which the vectorizer can give lanes only when
// it holds words alone: a dup or a drop, an allocation or a call in it is
// a count, a cell or a function per element.
LogicalResult pureArrayLoops(ModuleOp module, StringRef function) {
  constexpr StringRef property = "pure-array-loops";
  SmallVector<Operation *> roots;
  if (function.empty()) {
    roots.push_back(module);
  } else {
    for (func::FuncOp fn : named(module, function, property))
      roots.push_back(fn);
    if (roots.empty())
      return failure();
  }
  bool held = true, found = false;
  auto impure = [](Operation *op) -> std::optional<StringRef> {
    if (isa<DupOp, DropOp>(op))
      return "changes a count";
    if (isa<CallOpInterface>(op))
      return "calls";
    auto effects = dyn_cast<MemoryEffectOpInterface>(op);
    if (!effects)
      return std::nullopt;
    SmallVector<MemoryEffects::EffectInstance> instances;
    effects.getEffects(instances);
    for (const MemoryEffects::EffectInstance &effect : instances)
      if (isa<MemoryEffects::Allocate>(effect.getEffect()) &&
          effect.getResource()->getResourceID() != LinResource::getResourceID())
        return "allocates";
    return std::nullopt;
  };
  for (Operation *root : roots)
    root->walk([&](Operation *loop) {
      if (!isa<ArrayGenerateOp, ArrayFoldOp>(loop))
        return;
      found = true;
      loop->getRegion(0).walk([&](Operation *op) {
        if (std::optional<StringRef> why = impure(op)) {
          fail(op->getLoc(), property) << op->getName() << " " << *why << " in the body of a "
                                       << loop->getName() << " in " << where(op);
          held = false;
        }
      });
    });
  if (!found) {
    fail(roots.front()->getLoc(), property) << "no loop over an array"
                                            << (function.empty() ? "" : " in ") << function;
    held = false;
  }
  return success(held);
}

// The roots a property of loops is checked under: the module, or the
// functions named.
static SmallVector<Operation *> rootsOf(ModuleOp module, StringRef function, StringRef property) {
  SmallVector<Operation *> roots;
  if (function.empty()) {
    roots.push_back(module);
    return roots;
  }
  for (func::FuncOp fn : named(module, function, property))
    roots.push_back(fn);
  return roots;
}

// A body the vectorizer takes: words alone, computed by arith and math ops
// and the loop's own indices.
static bool wordsAlone(linalg::GenericOp op) {
  for (Operation &inner : op.getRegion().front()) {
    if (isa<linalg::IndexOp, linalg::YieldOp>(inner))
      continue;
    StringRef dialect = inner.getDialect() ? inner.getDialect()->getNamespace() : "";
    if (inner.getNumRegions() != 0 || (dialect != "arith" && dialect != "math"))
      return false;
  }
  return true;
}

LogicalResult vectorized(ModuleOp module, StringRef function) {
  constexpr StringRef property = "vectorized";
  SmallVector<Operation *> roots = rootsOf(module, function, property);
  if (roots.empty())
    return failure();
  bool held = true, vectors = false;
  for (Operation *root : roots)
    root->walk([&](Operation *op) {
      if (isa_and_nonnull<vector::VectorDialect>(op->getDialect()))
        vectors = true;
      auto generic = dyn_cast<linalg::GenericOp>(op);
      if (!generic || llvm::none_of(generic.getIteratorTypesArray(), linalg::isParallelIterator) ||
          !wordsAlone(generic))
        return;
      fail(op->getLoc(), property) << "a loop over words with a parallel dimension stayed scalar in "
                                   << where(op);
      held = false;
    });
  if (!vectors) {
    fail(roots.front()->getLoc(), property) << "no loop computes on vectors"
                                            << (function.empty() ? "" : " in ") << function;
    held = false;
  }
  return success(held);
}

// The widest integer lane `op` computes, in bits: an elementwise op on
// vectors of integers that computes (no cast, and no select, which move
// lanes and cost the same at any width); 0 when it is no such op.
static unsigned laneBits(Operation *op) {
  if (!op->hasTrait<OpTrait::Elementwise>() || isa<CastOpInterface, arith::SelectOp>(op))
    return 0;
  unsigned bits = 0;
  auto note = [&](Type type) {
    if (isa<VectorType>(type))
      bits = std::max(bits, ConstantIntRanges::getStorageBitwidth(type));
  };
  for (Type type : op->getOperandTypes())
    note(type);
  for (Type type : op->getResultTypes())
    note(type);
  return bits;
}

// The widest integer lane the loop `loop` computes, in bits; 0 when none.
static unsigned widestLane(Operation *loop) {
  unsigned bits = 0;
  loop->walk([&](Operation *op) { bits = std::max(bits, laneBits(op)); });
  return bits;
}

LogicalResult narrowedLanes(ModuleOp module, StringRef function) {
  constexpr StringRef property = "narrowed-lanes";
  SmallVector<Operation *> roots = rootsOf(module, function, property);
  if (roots.empty())
    return failure();
  bool held = true, narrow = false;
  for (Operation *root : roots)
    root->walk([&](scf::ForOp loop) {
      // The outermost loop of a nest speaks for the nest.
      if (loop->getParentOfType<scf::ForOp>())
        return;
      unsigned bits = widestLane(loop);
      if (bits == 0)
        return;
      if (bits <= 32) {
        narrow = true;
        return;
      }
      // A loop that runs at most once has no version to pay for.
      if (idr::graph::runsAtMostOnce(loop))
        return;
      // The 64-bit version stands in the else region of a version whose
      // then region holds a loop computing its lanes in 32 bits.
      bool paired = false;
      for (Operation *parent = loop->getParentOp(); parent && !paired; parent = parent->getParentOp()) {
        auto version = dyn_cast<scf::IfOp>(parent);
        if (!version || !version.getElseRegion().isAncestor(loop->getParentRegion()))
          continue;
        version.getThenRegion().walk([&](scf::ForOp other) {
          unsigned narrowed = widestLane(other);
          paired |= narrowed != 0 && narrowed <= 32;
        });
      }
      if (paired)
        return;
      fail(loop.getLoc(), property) << "a loop computes integer lanes of " << bits
                                    << " bits with no 32-bit version in " << where(loop);
      held = false;
    });
  if (!narrow) {
    fail(roots.front()->getLoc(), property) << "no loop computes integer lanes in 32 bits"
                                            << (function.empty() ? "" : " in ") << function;
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
