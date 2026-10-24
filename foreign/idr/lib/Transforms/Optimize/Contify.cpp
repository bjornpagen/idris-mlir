// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-contify: a function that always returns to one place becomes a join
// point there, where its body is moved and its calls jumps.
//
// It is an optimization and promises nothing. A continuation the program
// as written makes is an idr.join, or an idr.loop where it recurses, from
// the frontend on, and no pass makes one a function again. Contify finds
// the rest: a function that happens to return to one place, as a
// definition called from one continuation does, or as inlining and
// specialization leave one. A function it leaves a function is no error,
// only a call that stays a call.
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
// where the group stands in a function, the region gives on to that
// function's return, and the call is a tail call still; where it stands at
// a continuation, the region gives on to the code after the call, and the
// call is no longer in tail position, which only ever loses a tail position
// at a continuation the program already had, so no stack grows that the
// program as written did not grow. A call of the function the group moves
// into is a self call there, and takes the context the rule reads off it.

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
#include "llvm/ADT/SmallVectorExtras.h"

#include <cstdint>
#include <optional>

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
// has none; the root is its own.
idr::footprint::Vector<std::optional<unsigned>> dominators(ArrayRef<SmallVector<unsigned, 2>> succ) {
  unsigned n = static_cast<unsigned>(succ.size());
  // Each reached node's place in the postorder; an unreached node's is
  // never read, since no walk up the tree meets it.
  idr::footprint::Vector<unsigned> order(n, 0);
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
      // The postorder holds each of the n nodes at most once.
      order[node] = static_cast<unsigned>(post.size());
      post.push_back(node);
      stack.pop_back();
    }
  }
  idr::footprint::Vector<SmallVector<unsigned, 2>> pred(n);
  for (unsigned from = 0; from < n; ++from)
    for (unsigned to : succ[from])
      pred[to].push_back(from);
  idr::footprint::Vector<std::optional<unsigned>> idom(n);
  idom[0] = 0u;
  // Both start at nodes with a dominator, and every node a walk up from one
  // meets has one: the walk follows dominators already set.
  auto intersect = [&](unsigned a, unsigned b) {
    while (a != b) {
      while (order[a] < order[b])
        a = *idom[a];
      while (order[b] < order[a])
        b = *idom[b];
    }
    return a;
  };
  bool changed = true;
  while (changed) {
    changed = false;
    for (unsigned node : llvm::reverse(post)) {
      if (node == 0)
        continue;
      std::optional<unsigned> chosen;
      for (unsigned p : pred[node])
        if (idom[p])
          chosen = chosen ? intersect(p, *chosen) : p;
      if (chosen && idom[node] != chosen) {
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
      if (idr::tailCallOf(call)) {
        succ[nodeOf(self)].push_back(callee);
        return;
      }
      auto k = static_cast<unsigned>(nodes.size());
      nodes.push_back(Continuation{call, self});
      succ.emplace_back();
      succ[0].push_back(k);
      succ[k].push_back(callee);
    });
  idr::footprint::Vector<std::optional<unsigned>> idom = dominators(succ);
  // The node that immediately dominates `node`, a function or a
  // continuation; none where the root does, or where the root does not
  // reach `node`.
  auto above = [&](unsigned node) -> std::optional<unsigned> {
    std::optional<unsigned> up = idom[node];
    if (!up || *up == 0)
      return std::nullopt;
    return up;
  };

  // Each function's place: the continuation or the function its group
  // stands at, read down the dominator tree, a function placed into a
  // function that is placed in turn going where that one goes. Each step
  // goes up the dominator tree, so the walk ends below the root. `up` is
  // the node immediately above a function's.
  auto placeOf = [&](unsigned up) {
    auto isFunction = [&](unsigned node) {
      return idr::match(
          nodes[node], [](Root) { return false; }, [](Function) { return true; },
          [](const Continuation &) { return false; });
    };
    for (std::optional<unsigned> next = above(up); next && isFunction(up); next = above(up))
      up = *next;
    return up;
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
    std::optional<unsigned> up = above(nodeOf(f));
    if (!up)
      continue;
    unsigned place = placeOf(*up);
    std::optional<unsigned> &at = groupAt[place];
    if (!at) {
      at = static_cast<unsigned>(groups.size());
      groups.push_back(Placement{place, {}});
    }
    groups[*at].members.push_back(f);
  }
  // A place is a function or a continuation, one below the root at least.
  auto depth = [&](unsigned node) {
    unsigned d = 1;
    for (std::optional<unsigned> up = above(node); up; up = above(*up))
      ++d;
    return d;
  };
  llvm::stable_sort(groups, [&](const Placement &a, const Placement &b) {
    return depth(a.place) > depth(b.place);
  });

  IRRewriter rewriter(program.getContext());
  // Each call left in a body a group just moved into `host`, once the jumps
  // replaced its sites: a tail call stays one where the group's place keeps
  // tails (a function's own body, whose return the group gives on to), every
  // other call ends no tail, and one of `host` itself, a self call now,
  // takes its context where it now stands. Every other call stands where it
  // stood. A body moved again by a group placed later is written again
  // there.
  enum class Place : std::uint8_t { KeepsTails, Continuation };
  auto placeMoved = [](Region &moved, idr::FuncOp host, Place place) {
    moved.walk([&](idr::CallOp call) {
      if (place == Place::KeepsTails && idr::tailCallOf(call))
        return;
      if (call.getCalleeAttr().getAttr() == host.getSymNameAttr())
        call.setTailKind(idr::tail::withContext(call));
      else
        call.setTailKind(idr::TailKind::nontail);
    });
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
        if (!target || !idr::tailCallOf(call))
          return;
        sites.push_back(idr::joins::Site{call, *target + shift, call.getArgs(),
                                         call.getIndexArgsAttr()});
        if (from)
          edges.push_back(idr::joins::Edge{*from, *target + shift});
      });
    };
    // Whether the loop the group makes may not end: what Idris proved of the
    // members it moves in, read before they are erased.
    SmallVector<idr::FuncOp> memberFns;
    for (FunctionId fn : members)
      memberFns.push_back(graph.op(fn));
    idr::joins::Ending ending = idr::joins::endingOf(memberFns);
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
            // Each fresh argument stands for the parameter it is passed to
            // and takes its location, the binder's identity, so a pass that
            // later dissolves the region leaves that identity on the
            // argument that took the parameter's place.
            idr::FuncOp h = graph.op(host.fn);
            sitesIn(h.getBody(), 0u, 1);
            for (auto [i, fn] : llvm::enumerate(members))
              sitesIn(graph.op(fn).getBody(), static_cast<unsigned>(i) + 1, 1);
            Region moved;
            moved.takeBody(h.getBody());
            SmallVector<idr::joins::Member> all{idr::joins::Member{&moved, h.getBindersAttr(), 0}};
            llvm::append_range(all, regions);
            SmallVector<Location> locations = llvm::map_to_vector(
                moved.front().getArguments(), [](BlockArgument parameter) { return parameter.getLoc(); });
            Block *entry = rewriter.createBlock(&h.getBody(), {}, h.getArgumentTypes(), locations);
            rewriter.setInsertionPointToStart(entry);
            idr::joins::Group group =
                idr::joins::build(rewriter, h.getLoc(), h.getResultTypes(), all, edges, ending);
            rewriter.setInsertionPointToEnd(group.body);
            // Each binder is a level, and a level is a 32-bit number.
            auto own = static_cast<std::uint32_t>(h.getBinders().getSorts().size());
            idr::IndexArgsAttr levels =
                own ? idr::families::levelArgs(h.getContext(), 0, own) : idr::IndexArgsAttr();
            idr::JumpOp::create(rewriter, h.getLoc(), group.targets.tokenFor(0, group.body->getParent()),
                                entry->getArguments(), levels);
            rewriter.setInsertionPointAfter(group.outermost);
            idr::ReturnOp::create(rewriter, h.getLoc(), group.outermost->getResults());
            for (const idr::joins::Site &site : sites)
              idr::joins::jumpAt(rewriter, site,
                                 group.targets.tokenFor(site.target, site.op->getParentRegion()));
            placeMoved(h.getBody(), h, Place::KeepsTails);
          },
          [&](const Continuation &k) {
            // The call that leaves for the group's entry is a site of the
            // body, which runs it and gives on what it gives. The node is
            // read through a const reference and the call it names is
            // rewritten: its handle is copied out, as an op is passed.
            idr::CallOp call = k.call;
            for (auto [i, fn] : llvm::enumerate(members))
              sitesIn(graph.op(fn).getBody(), static_cast<unsigned>(i), 0);
            sites.push_back(idr::joins::Site{call, *memberOf[graph.id(call.getCalleeAttr())],
                                             call.getArgs(), call.getIndexArgsAttr()});
            // The function the call stands in now, which a group placed
            // earlier may have moved it into.
            auto in = call->getParentOfType<idr::FuncOp>();
            Operation *outer = idr::joins::wrap(rewriter, call, regions, sites, ending);
            for (Region &region : outer->getRegions())
              placeMoved(region, in, Place::Continuation);
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
