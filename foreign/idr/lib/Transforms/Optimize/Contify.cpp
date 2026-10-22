// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-contify: a function that always returns to one place becomes a join
// point there, where its body is moved and its calls jumps.
//
// Where a function returns is read off one dominator tree over the
// functions, the continuations of the non-tail calls, and a root: a
// non-tail call of f leaves for f from its own continuation, a tail call of
// f from g leaves for f from g (f returns where g does), and the root
// reaches every continuation and the program's entry. A function whose
// immediate dominator is a continuation always returns there: it, and
// every function it dominates in turn, become a group of join points around
// that call. One whose immediate dominator is a function h always returns
// where h does: it becomes a join point of h, reached by h's tail calls. A
// function the root alone dominates returns to more than one place and
// stays a function. Nothing is copied, so nothing is budgeted.
//
// A call in a moved body that ended its function now ends a join region:
// where the group stands at a continuation, the region gives on to the code
// after the call, and the call is no longer in tail position. Its tail fact
// is the one definition's answer where it now stands, and that answer only
// ever loses a tail position at a continuation the program already had,
// so no stack grows that the program as written did not grow.

#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/IR/Families/Substitute.h"
#include "idr/IR/Func.h"
#include "idr/IR/Generated/Actions.h.inc"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Tail.h"
#include "idr/Support/Actions.h"
#include "idr/Support/Footprint.h"
#include "idr/Transforms/Joins.h"
#include "idr/Transforms/Optimize.h"

#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/STLExtras.h"

#define GEN_PASS_DEF_IDRCONTIFY
#include "idr/IR/Generated/PassDialects.h.inc"

namespace idr {
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace {

// One group's placement, as its IR unit: the call it stands around, or the
// function whose join points it becomes.
struct ContifyAction : idr::support::TaggedAction<ContifyAction> {
  using TaggedAction::TaggedAction;
  static constexpr std::string_view tag = ::idr::actions::contifyGroup;
};

using idr::solver::FunctionId;

// A node of the return graph: the root, a function, or the continuation of
// one non-tail call.
struct Root {};
struct Function {
  FunctionId fn;
};
struct Continuation {
  idr::CallOp call;
  FunctionId in;
};
using Node = std::variant<Root, Function, Continuation>;

// The immediate dominators of a graph given as successor lists from node 0:
// the iterative algorithm of Cooper, Harvey and Kennedy over a reverse
// postorder, each walk with its own stack. A node the root does not reach
// has none.
idr::footprint::Vector<int> dominators(ArrayRef<SmallVector<unsigned, 2>> succ) {
  unsigned n = static_cast<unsigned>(succ.size());
  idr::footprint::Vector<int> order(n, -1);
  idr::footprint::Vector<unsigned> post;
  {
    idr::footprint::Vector<std::pair<unsigned, unsigned>> stack{{0, 0}};
    idr::footprint::Vector<char> seen(n, 0);
    seen[0] = 1;
    while (!stack.empty()) {
      auto &[node, next] = stack.back();
      if (next < succ[node].size()) {
        unsigned to = succ[node][next++];
        if (!seen[to]) {
          seen[to] = 1;
          stack.push_back({to, 0});
        }
        continue;
      }
      order[node] = static_cast<int>(post.size());
      post.push_back(node);
      stack.pop_back();
    }
  }
  idr::footprint::Vector<SmallVector<unsigned, 2>> pred(n);
  for (unsigned from = 0; from < n; ++from)
    for (unsigned to : succ[from])
      pred[to].push_back(from);
  idr::footprint::Vector<int> idom(n, -1);
  idom[0] = 0;
  auto intersect = [&](int a, int b) {
    while (a != b) {
      while (order[a] < order[b])
        a = idom[a];
      while (order[b] < order[a])
        b = idom[b];
    }
    return a;
  };
  bool changed = true;
  while (changed) {
    changed = false;
    for (unsigned node : llvm::reverse(post)) {
      if (node == 0)
        continue;
      int chosen = -1;
      for (unsigned p : pred[node])
        if (idom[p] >= 0)
          chosen = chosen < 0 ? static_cast<int>(p) : intersect(static_cast<int>(p), chosen);
      if (chosen >= 0 && idom[node] != chosen) {
        idom[node] = chosen;
        changed = true;
      }
    }
  }
  return idom;
}

// How many groups a run placed. A function is read by the program's one
// numbering of its functions, `graph`, never by its name.
unsigned contify(idr::ProgramOp program, const idr::solver::ProgramGraph &graph) {
  // The return graph: node 0 the root, then a node per function id (one
  // with no function a node no edge reaches), then one per non-tail call.
  auto nodeOf = [](FunctionId f) { return 1 + f.index(); };
  idr::footprint::Vector<Node> nodes{Root{}};
  for (FunctionId f : graph.size().ids())
    nodes.push_back(Function{f});
  idr::footprint::Vector<SmallVector<unsigned, 2>> succ(nodes.size());
  succ[0].push_back(nodeOf(graph.id(program.getRootAttr())));
  for (FunctionId self : graph.functions())
    graph.op(self).walk([&](idr::CallOp call) {
      unsigned callee = nodeOf(graph.id(call.getCalleeAttr()));
      if (call.getTailKind() == idr::TailKind::tail) {
        succ[nodeOf(self)].push_back(callee);
        return;
      }
      auto k = static_cast<unsigned>(nodes.size());
      nodes.push_back(Continuation{call, self});
      succ.emplace_back();
      succ[0].push_back(k);
      succ[k].push_back(callee);
    });
  idr::footprint::Vector<int> idom = dominators(succ);

  // Each function's place: the continuation or the function its group
  // stands at, read down the dominator tree, a function placed into a
  // function that is placed in turn going where that one goes. Each step
  // goes up the dominator tree, so the walk ends at the root.
  auto placeOf = [&](unsigned node) {
    unsigned at = node;
    for (int up = idom[at]; up > 0; at = static_cast<unsigned>(up), up = idom[at]) {
      bool function = idr::match(
          nodes[up], [](Root) { return false; }, [](Function) { return true; },
          [](const Continuation &) { return false; });
      if (!function || idom[up] <= 0)
        return static_cast<unsigned>(up);
    }
    return at;
  };
  // The groups, each its place's node and its members in the numbering's
  // order, found by the place's node; placed deepest first, so a group
  // placed inside a function moves before that function moves.
  struct Placement {
    unsigned place;
    SmallVector<FunctionId> members;
  };
  idr::footprint::Vector<Placement> groups;
  idr::footprint::Vector<std::optional<unsigned>> groupAt(nodes.size());
  for (FunctionId f : graph.functions()) {
    unsigned node = nodeOf(f);
    if (idom[node] <= 0)
      continue;
    unsigned place = placeOf(node);
    std::optional<unsigned> &at = groupAt[place];
    if (!at) {
      at = static_cast<unsigned>(groups.size());
      groups.push_back(Placement{place, {}});
    }
    groups[*at].members.push_back(f);
  }
  auto depth = [&](unsigned node) {
    unsigned d = 0;
    for (int at = static_cast<int>(node); at > 0; at = idom[at])
      ++d;
    return d;
  };
  llvm::stable_sort(groups, [&](const Placement &a, const Placement &b) {
    return depth(a.place) > depth(b.place);
  });

  IRRewriter rewriter(program.getContext());
  // Each call left in a body a group just moved, its tail fact where it now
  // stands; every other call stands where it stood. A body moved again by
  // a group placed later is decided again there.
  auto decideMoved = [](Region &moved) {
    moved.walk([](idr::CallOp call) { call.setTailKind(idr::tail::decide(call)); });
  };
  unsigned placed = 0;
  // Each function's place among the members of the group being placed, by
  // its id; none for any other.
  idr::IndexVector<FunctionId, std::optional<unsigned>> memberOf =
      graph.table<std::optional<unsigned>>(std::nullopt);
  for (const Placement &placing : groups) {
    unsigned place = placing.place;
    ArrayRef<FunctionId> members = placing.members;
    for (auto [i, fn] : llvm::enumerate(members))
      memberOf[fn] = static_cast<unsigned>(i);
    SmallVector<idr::joins::Member> regions;
    for (FunctionId fn : members) {
      idr::FuncOp f = graph.op(fn);
      regions.push_back(idr::joins::Member{&f.getBody(), f.getBindersAttr(), 0});
    }
    // Each tail call of a member, from a member or from the place's own
    // body, a site of the group, and an edge of its jump graph from the
    // member it stands in.
    SmallVector<idr::joins::Site> sites;
    SmallVector<idr::joins::Edge> edges;
    auto sitesIn = [&](Region &region, std::optional<unsigned> from, unsigned shift) {
      region.walk([&](idr::CallOp call) {
        std::optional<unsigned> target = memberOf[graph.id(call.getCalleeAttr())];
        if (!target || call.getTailKind() != idr::TailKind::tail)
          return;
        sites.push_back(idr::joins::Site{call, *target + shift, call.getArgs(),
                                         call.getIndexArgsAttr()});
        if (from)
          edges.push_back(idr::joins::Edge{*from, *target + shift});
      });
    };
    Operation *unit = idr::match(
        nodes[place], [&](Root) -> Operation * { return program; },
        [&](Function host) -> Operation * { return graph.op(host.fn); },
        [&](const Continuation &k) -> Operation * { return k.call; });
    (void)idr::support::perform<ContifyAction>(unit, [&] {
      idr::match(
          nodes[place], [](Root) {},
          [&](Function host) {
            // The host's body becomes the group's first join region, which
            // a fresh entry jumps to with the host's arguments and its own
            // index variables; its tail calls of members are sites too.
            idr::FuncOp h = graph.op(host.fn);
            sitesIn(h.getBody(), 0u, 1);
            for (auto [i, fn] : llvm::enumerate(members))
              sitesIn(graph.op(fn).getBody(), static_cast<unsigned>(i) + 1, 1);
            Region moved;
            moved.takeBody(h.getBody());
            SmallVector<idr::joins::Member> all{idr::joins::Member{&moved, h.getBindersAttr(), 0}};
            llvm::append_range(all, regions);
            Block *entry = rewriter.createBlock(&h.getBody(), {}, h.getArgumentTypes(),
                                                SmallVector<Location>(h.getNumArguments(), h.getLoc()));
            rewriter.setInsertionPointToStart(entry);
            idr::joins::Group group =
                idr::joins::build(rewriter, h.getLoc(), h.getResultTypes(), all, edges);
            rewriter.setInsertionPointToEnd(group.body);
            unsigned own = h.getBindersAttr() ? h.getBindersAttr().getSorts().size() : 0;
            idr::IndexArgsAttr levels =
                own ? idr::families::levelArgs(h.getContext(), 0, own) : idr::IndexArgsAttr();
            idr::JumpOp::create(rewriter, h.getLoc(), group.targets.tokenFor(0, group.body->getParent()),
                                entry->getArguments(), levels);
            rewriter.setInsertionPointAfter(group.outermost);
            idr::ReturnOp::create(rewriter, h.getLoc(), group.outermost->getResults());
            for (const idr::joins::Site &site : sites)
              idr::joins::jumpAt(rewriter, site,
                                 group.targets.tokenFor(site.target, site.op->getParentRegion()));
            decideMoved(h.getBody());
          },
          [&](const Continuation &k) {
            // The call that leaves for the group's entry is a site of the
            // body, which runs it and gives on what it gives.
            for (auto [i, fn] : llvm::enumerate(members))
              sitesIn(graph.op(fn).getBody(), static_cast<unsigned>(i), 0);
            sites.push_back(idr::joins::Site{k.call, *memberOf[graph.id(k.call.getCalleeAttr())],
                                             k.call.getArgs(), k.call.getIndexArgsAttr()});
            Operation *outer = idr::joins::wrap(rewriter, k.call, regions, sites);
            for (Region &region : outer->getRegions())
              decideMoved(region);
          });
      for (FunctionId fn : members)
        rewriter.eraseOp(graph.op(fn));
      ++placed;
    });
    for (FunctionId fn : members)
      memberOf[fn] = std::nullopt;
  }
  return placed;
}

struct Contify : idr::impl::IdrContifyBase<Contify> {
  void runOnProgram(idr::ProgramOp program) {
    unsigned placed = contify(program, getAnalysis<idr::solver::ProgramGraph>());
    numContified += placed;
    if (placed == 0)
      return markAllAnalysesPreserved();
  }
};

} // namespace
