// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//===----------------------------------------------------------------------===//
// Copyright (c) 2026, Modular Inc. All rights reserved.
//
// Licensed under the Apache License v2.0 with LLVM Exceptions:
// https://llvm.org/LICENSE.txt
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//===----------------------------------------------------------------------===//
// Modified by Bjorn Pagen, 2026, from Modular's 9211931: on idr.func, with a reference graph, llvm::scc_iterator and MLIR's thread pool for KGEN's call graph and AsyncRT, classes compared by idr::deduplicate, every use renamed and the copies erased.
// PIN(eliminate-duplicate-functions)
//
// idr-deduplicate: of each class of private idr.funcs that are one function
// twice over, the lexicographically smallest stays, every use of the others
// names it, and the others are erased.
//
// Monomorphisation writes one function per instantiation, and what Idris
// erased is gone from some of them alike, so a stage0 module holds
// thousands of second copies, each work for every later pass. Merging runs
// bottom-up over the reference graph, so that when two callers are
// compared their callees are already merged and renamed: callers that
// differ only in which copy they call become one class in the same run, and
// a second run finds nothing.
//
// A function is a candidate when it is private, is no member of a cycle of
// two or more functions, and every use of it may be renamed: in its own
// body, or a call's callee, a closure's or a suspension's label, or a
// closure constant. Any other use (a constructor naming a label, an
// attribute of a function, an op outside every function) names the
// function for itself, not for what it computes.
//
// The graph's components are processed by height, so a class, whose
// members always share a height, is whole before any function above it
// reads its kept name. Within one height the renaming and the hashing run
// in parallel and the classes are formed serially in module order; the
// kept name is a function of the class alone, so the output is the same at
// any thread count.

#include "idr/Transforms/Deduplicate.h"

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/AttrTypeSubElements.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Location.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/IR/Threading.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/SCCIterator.h"
#include "llvm/ADT/STLExtras.h"

#include <algorithm>
#include <vector>

namespace idr {
#define GEN_PASS_DEF_IDRDEDUPLICATE
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace {

// A function that may be merged, with its hash, computed once.
struct Candidate {
  idr::FuncOp func;
  unsigned hash;
};

struct DuplicateFuncOpEquivalenceInfo {
  static unsigned getHashValue(const Candidate &candidate) { return candidate.hash; }

  static bool isEqual(const Candidate &lhs, const Candidate &rhs) {
    if (lhs.func == rhs.func)
      return true;
    return lhs.hash == rhs.hash && idr::deduplicate::sameFunction(lhs.func, rhs.func);
  }
};

// One function of the module, what it names, and where it sits in the
// graph's order.
struct Node {
  idr::FuncOp func;
  // The other functions it names, each once, in the order they are met.
  llvm::SmallVector<Node *> callees;
  // Whether every use of it may be renamed.
  bool renamable = true;
  // Whether it is a member of a cycle of two or more functions.
  bool cyclic = false;
  unsigned component = 0;
  unsigned height = 0;

  bool isCandidate() { return func.isPrivate() && renamable && !cyclic; }
};

// Whether a reference that `user` holds may be renamed to another function
// that computes the same: a call's callee, a closure's or a suspension's
// label, a closure constant.
bool isRenamable(Operation *user) {
  if (isa<idr::CallOp, idr::ClosureOp, idr::SuspendOp>(user))
    return true;
  auto constant = dyn_cast<idr::ConstantOp>(user);
  return constant && isa<idr::ClosureAttr>(constant.getValue());
}

// Each symbol reference `op` holds, as SymbolTable finds uses: in its
// discardable and inherent attributes, never inside a reference's nested
// part.
template <typename Fn>
void forEachReference(Operation *op, Fn &&fn) {
  auto walk = [&](Attribute attr) {
    attr.walk<WalkOrder::PreOrder>([&](SymbolRefAttr ref) {
      fn(ref);
      return WalkResult::skip();
    });
  };
  walk(op->getRawDictionaryAttrs());
  op->getName().walkInherentAttrs(op, [&](StringRef, Attribute &attr) { walk(attr); });
}

struct CallGraph {
  explicit CallGraph(ModuleOp module);

  // Tarjan's components, callees first, and each function's height.
  void order();

  // Every function the graph holds, by height, in module order.
  llvm::SmallVector<llvm::SmallVector<Node *>> byHeight();

  // External node that has every function as a callee. This node is the
  // entry node of the graph for computing SCCs.
  Node externalNode;
  // In module order. Sized once, so that the pointers into it stay.
  std::vector<Node> nodes;
};

} // namespace

namespace llvm {
template <> struct GraphTraits<CallGraph *> {
  using NodeRef = Node *;
  using ChildIteratorType = SmallVectorImpl<Node *>::iterator;
  static NodeRef getEntryNode(CallGraph *graph) { return &graph->externalNode; }
  static ChildIteratorType child_begin(NodeRef node) { return node->callees.begin(); }
  static ChildIteratorType child_end(NodeRef node) { return node->callees.end(); }
};
} // namespace llvm

namespace {

CallGraph::CallGraph(ModuleOp module) {
  auto functions = llvm::to_vector(module.getOps<idr::FuncOp>());
  nodes.resize(functions.size());
  DenseMap<StringAttr, Node *> byName;
  for (auto [node, func] : llvm::zip_equal(nodes, functions)) {
    node.func = func;
    byName[func.getSymNameAttr()] = &node;
  }

  // What each function names, found in parallel: the node each reference
  // names, and whether the op holding it may have it renamed.
  struct Reference {
    Node *target;
    bool renamable;
  };
  std::vector<llvm::SmallVector<Reference>> found(nodes.size());
  parallelFor(module.getContext(), 0, nodes.size(), [&](size_t index) {
    Node &node = nodes[index];
    auto record = [&](Operation *user, SymbolRefAttr ref) {
      if (Node *target = byName.lookup(ref.getRootReference()))
        found[index].push_back({target, user != node.func.getOperation() && isRenamable(user)});
    };
    forEachReference(node.func, [&](SymbolRefAttr ref) { record(node.func, ref); });
    node.func.getBody().walk([&](Operation *user) {
      forEachReference(user, [&](SymbolRefAttr ref) { record(user, ref); });
    });
  });

  for (auto [node, references] : llvm::zip_equal(nodes, found)) {
    DenseSet<Node *> seen;
    for (Reference reference : references) {
      // A function's uses of itself go with its body, whichever stays.
      if (reference.target == &node)
        continue;
      reference.target->renamable &= reference.renamable;
      if (seen.insert(reference.target).second)
        node.callees.push_back(reference.target);
    }
  }
  // A function named outside every function is named for itself.
  for (Operation &op : *module.getBody()) {
    if (isa<idr::FuncOp>(op))
      continue;
    op.walk([&](Operation *user) {
      forEachReference(user, [&](SymbolRefAttr ref) {
        if (Node *target = byName.lookup(ref.getRootReference()))
          target->renamable = false;
      });
    });
  }

  // We add an edge from externalNode to every other node. Note that it would
  // *NOT* change the topology of the callgraph nor does it introduce extra
  // cycles into the callgraph, as there is no incoming edge to the external
  // node. This is needed because the pass runs before dead code is removed,
  // so cycles of functions nothing calls must be visited too.
  for (Node &node : nodes)
    externalNode.callees.push_back(&node);
}

void CallGraph::order() {
  unsigned component = 0;
  for (auto scc = llvm::scc_begin(this); scc != llvm::scc_end(this); ++scc) {
    const std::vector<Node *> &members = *scc;
    if (members.front() == &externalNode)
      continue;
    ++component;
    for (Node *member : members)
      member->component = component;
    unsigned height = 0;
    for (Node *member : members)
      for (Node *callee : member->callees)
        if (callee->component != component)
          height = std::max(height, callee->height + 1);
    // Cycles need extra handling: their members are never deduplicated,
    // since one renamed into another would rewrite the recursion between
    // them into a recursion the comparison did not prove.
    for (Node *member : members) {
      member->height = height;
      member->cyclic = members.size() > 1;
    }
  }
}

llvm::SmallVector<llvm::SmallVector<Node *>> CallGraph::byHeight() {
  unsigned top = 0;
  for (Node &node : nodes)
    top = std::max(top, node.height);
  llvm::SmallVector<llvm::SmallVector<Node *>> heights(nodes.empty() ? 0 : top + 1);
  for (Node &node : nodes)
    heights[node.height].push_back(&node);
  return heights;
}

// Renames each reference in `func`'s body to a function merged below it to
// the one kept of that function's class.
void replaceCallSitesWithLexMin(idr::FuncOp func, const DenseMap<StringAttr, StringAttr> &kept) {
  if (kept.empty())
    return;
  AttrTypeReplacer replacer;
  replacer.addReplacement([&](SymbolRefAttr ref) -> std::optional<std::pair<Attribute, WalkResult>> {
    StringAttr name = kept.lookup(ref.getRootReference());
    if (!name)
      return std::make_pair(Attribute(ref), WalkResult::skip());
    return std::make_pair(Attribute(SymbolRefAttr::get(name, ref.getNestedReferences())), WalkResult::skip());
  });
  func.getBody().walk([&](Operation *op) { replacer.replaceElementsIn(op); });
}

struct EliminateDuplicateFunctionsPass
    : idr::impl::IdrDeduplicateBase<EliminateDuplicateFunctionsPass> {
  void runOnOperation() override;
};

void EliminateDuplicateFunctionsPass::runOnOperation() {
  ModuleOp module = getOperation();
  MLIRContext *context = &getContext();
  CallGraph graph(module);
  graph.order();

  // Maps each merged function's name to the lexicographically smallest
  // symbol of its class, and holds each class of two or more, its members
  // in symbol order.
  DenseMap<StringAttr, StringAttr> representativeToLexMin;
  llvm::SmallVector<llvm::SmallVector<idr::FuncOp>> classes;

  for (llvm::SmallVector<Node *> &height : graph.byHeight()) {
    std::vector<unsigned> hashes(height.size());
    parallelFor(context, 0, height.size(), [&](size_t index) {
      Node *node = height[index];
      replaceCallSitesWithLexMin(node->func, representativeToLexMin);
      if (node->isCandidate())
        hashes[index] = static_cast<unsigned>(
            static_cast<size_t>(idr::deduplicate::hashFunction(node->func)));
    });

    // Each candidate joins the class of the first one before it that is
    // the same function, or begins one.
    DenseSet<Candidate, DuplicateFuncOpEquivalenceInfo> uniqueFuncSet;
    llvm::SmallVector<llvm::SmallVector<idr::FuncOp>> formed;
    DenseMap<Operation *, size_t> classOf;
    for (auto [node, hash] : llvm::zip_equal(height, hashes)) {
      if (!node->isCandidate())
        continue;
      auto [representative, inserted] = uniqueFuncSet.insert({node->func, hash});
      if (inserted) {
        classOf[node->func] = formed.size();
        formed.push_back({node->func});
      } else {
        formed[classOf.lookup(representative->func)].push_back(node->func);
      }
    }

    // Once the classes of this height are formed, every reference above it
    // to one of their members is renamed to the smallest symbol of its
    // class.
    for (llvm::SmallVector<idr::FuncOp> &members : formed) {
      if (members.size() < 2)
        continue;
      llvm::sort(members, [](idr::FuncOp lhs, idr::FuncOp rhs) {
        return lhs.getSymName() < rhs.getSymName();
      });
      for (idr::FuncOp member : llvm::drop_begin(members))
        representativeToLexMin[member.getSymNameAttr()] = members.front().getSymNameAttr();
      classes.push_back(std::move(members));
    }
  }

  if (classes.empty())
    return markAllAnalysesPreserved();

  // The one kept carries every member's location, so that what was written
  // for any of them finds it.
  for (llvm::SmallVector<idr::FuncOp> &members : classes) {
    auto locations = llvm::map_to_vector(members, [](idr::FuncOp member) { return member.getLoc(); });
    members.front()->setLoc(FusedLoc::get(context, locations));
  }
  numGroups += classes.size();

  // A duplicate is used only by itself now: every other use was renamed in
  // its user's height. Erased serially, in module order.
  SymbolTable &symbols = getAnalysis<SymbolTable>();
  for (Node &node : graph.nodes) {
    if (!representativeToLexMin.contains(node.func.getSymNameAttr()))
      continue;
    symbols.erase(node.func);
    ++numMerged;
  }
  markAnalysesPreserved<SymbolTable>();
}

} // namespace
