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
#include "idr/IR/Func.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Tail.h"
#include "idr/Support/Actions.h"
#include "idr/Transforms/Joins.h"
#include "idr/Transforms/Optimize.h"

#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/STLExtras.h"

namespace idr {
#define GEN_PASS_DEF_IDRCONTIFY
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace {

// One group's placement, as its IR unit: the call it stands around, or the
// function whose join points it becomes.
struct ContifyAction : idr::support::TaggedAction<ContifyAction> {
  using TaggedAction::TaggedAction;
  static constexpr llvm::StringLiteral tag = "idr-contify-group";
};

// A node of the return graph: the root, a function, or the continuation of
// one non-tail call.
struct Root {};
struct Function {
  unsigned fn;
};
struct Continuation {
  idr::CallOp call;
  unsigned in;
};
using Node = std::variant<Root, Function, Continuation>;

// The immediate dominators of a graph given as successor lists from node 0:
// the iterative algorithm of Cooper, Harvey and Kennedy over a reverse
// postorder, each walk with its own stack. A node the root does not reach
// has none.
SmallVector<int> dominators(ArrayRef<SmallVector<unsigned, 2>> succ) {
  unsigned n = static_cast<unsigned>(succ.size());
  SmallVector<int> order(n, -1);
  SmallVector<unsigned> post;
  {
    SmallVector<std::pair<unsigned, unsigned>> stack{{0, 0}};
    SmallVector<char> seen(n, 0);
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
  SmallVector<SmallVector<unsigned, 2>> pred(n);
  for (unsigned from = 0; from < n; ++from)
    for (unsigned to : succ[from])
      pred[to].push_back(from);
  SmallVector<int> idom(n, -1);
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

// How many groups a run placed.
unsigned contify(idr::ProgramOp program) {
  SmallVector<idr::FuncOp> fns(program.getOps<idr::FuncOp>());
  llvm::DenseMap<StringAttr, unsigned> position;
  for (auto [at, fn] : llvm::enumerate(fns))
    position.try_emplace(fn.getSymNameAttr(), static_cast<unsigned>(at));
  // The return graph: node 0 the root, 1..F the functions, then one node
  // per non-tail call.
  SmallVector<Node> nodes{Root{}};
  for (unsigned at = 0; at < fns.size(); ++at)
    nodes.push_back(Function{at});
  SmallVector<SmallVector<unsigned, 2>> succ(nodes.size());
  succ[0].push_back(1 + position.find(program.getRootAttr().getAttr())->second);
  for (auto [at, fn] : llvm::enumerate(fns))
    fn.walk([&](idr::CallOp call) {
      unsigned callee = 1 + position.find(call.getCalleeAttr().getAttr())->second;
      if (call.getTail() == idr::TailKind::Tail) {
        succ[1 + at].push_back(callee);
        return;
      }
      auto k = static_cast<unsigned>(nodes.size());
      nodes.push_back(Continuation{call, static_cast<unsigned>(at)});
      succ.emplace_back();
      succ[0].push_back(k);
      succ[k].push_back(callee);
    });
  SmallVector<int> idom = dominators(succ);

  // Each function's place: the continuation or the function its group
  // stands at, read down the dominator tree, a function placed into a
  // function that is placed in turn going where that one goes.
  auto placeOf = [&](unsigned node) {
    unsigned at = node;
    while (true) {
      int up = idom[at];
      if (up <= 0)
        return at;
      bool function = idr::match(
          nodes[up], [](Root) { return false; }, [](Function) { return true; },
          [](const Continuation &) { return false; });
      if (!function)
        return static_cast<unsigned>(up);
      if (idom[up] <= 0)
        return static_cast<unsigned>(up);
      at = static_cast<unsigned>(up);
    }
  };
  // The groups, by place, each in program order; deepest first, so a group
  // placed inside a function moves before that function moves.
  llvm::DenseMap<unsigned, SmallVector<unsigned>> groups;
  SmallVector<unsigned> places;
  for (unsigned at = 0; at < fns.size(); ++at) {
    unsigned node = 1 + at;
    if (idom[node] <= 0)
      continue;
    unsigned place = placeOf(node);
    auto [found, fresh] = groups.try_emplace(place);
    if (fresh)
      places.push_back(place);
    found->second.push_back(at);
  }
  auto depth = [&](unsigned node) {
    unsigned d = 0;
    for (int at = static_cast<int>(node); at > 0; at = idom[at])
      ++d;
    return d;
  };
  llvm::stable_sort(places, [&](unsigned a, unsigned b) { return depth(a) > depth(b); });

  IRRewriter rewriter(program.getContext());
  unsigned placed = 0;
  for (unsigned place : places) {
    ArrayRef<unsigned> members = groups.find(place)->second;
    llvm::DenseMap<StringAttr, unsigned> memberOf;
    for (auto [i, fn] : llvm::enumerate(members))
      memberOf.try_emplace(fns[fn].getSymNameAttr(), static_cast<unsigned>(i));
    // Code Idris did not prove terminating loops only where it did before.
    idr::joins::Origin origin = llvm::all_of(members, [&](unsigned fn) {
                                  return static_cast<bool>(fns[fn].getTerminatesAttr());
                                })
                                    ? idr::joins::Origin::Terminates
                                    : idr::joins::Origin::MayDiverge;
    SmallVector<idr::joins::Member> regions;
    for (unsigned fn : members) {
      idr::FuncOp f = fns[fn];
      regions.push_back(idr::joins::Member{&f.getBody(), f.getBindersAttr(), 0});
    }
    // Each tail call of a member, from a member or from the place's own
    // body, a site of the group, and an edge of its jump graph from the
    // member it stands in.
    SmallVector<idr::joins::Site> sites;
    SmallVector<idr::joins::Edge> edges;
    auto sitesIn = [&](Region &region, std::optional<unsigned> from, unsigned shift) {
      region.walk([&](idr::CallOp call) {
        auto target = memberOf.find(call.getCalleeAttr().getAttr());
        if (target == memberOf.end() || call.getTail() != idr::TailKind::Tail)
          return;
        sites.push_back(idr::joins::Site{call, target->second + shift, call.getArgs(),
                                         call.getIndexArgsAttr()});
        if (from)
          edges.push_back(idr::joins::Edge{*from, target->second + shift});
      });
    };
    Operation *unit = idr::match(
        nodes[place], [&](Root) -> Operation * { return program; },
        [&](Function host) -> Operation * { return fns[host.fn]; },
        [&](const Continuation &k) -> Operation * { return k.call; });
    (void)idr::support::perform<ContifyAction>(unit, [&] {
      idr::match(
          nodes[place], [](Root) {},
          [&](Function host) {
            // The host's body becomes the group's first join region, which
            // a fresh entry jumps to with the host's arguments and its own
            // index variables; its tail calls of members are sites too.
            idr::FuncOp h = fns[host.fn];
            sitesIn(h.getBody(), 0u, 1);
            for (auto [i, fn] : llvm::enumerate(members))
              sitesIn(fns[fn].getBody(), static_cast<unsigned>(i) + 1, 1);
            Region moved;
            moved.takeBody(h.getBody());
            SmallVector<idr::joins::Member> all{idr::joins::Member{&moved, h.getBindersAttr(), 0}};
            llvm::append_range(all, regions);
            Block *entry = rewriter.createBlock(&h.getBody(), {}, h.getArgumentTypes(),
                                                SmallVector<Location>(h.getNumArguments(), h.getLoc()));
            rewriter.setInsertionPointToStart(entry);
            idr::joins::Group group =
                idr::joins::build(rewriter, h.getLoc(), h.getResultTypes(), all, edges, origin);
            rewriter.setInsertionPointToEnd(group.body);
            unsigned own = h.getBindersAttr() ? h.getBindersAttr().getSorts().size() : 0;
            idr::JumpOp::create(rewriter, h.getLoc(), group.targets.tokenFor(0, group.body->getParent()),
                                entry->getArguments(),
                                own ? idr::families::levelArgs(h.getContext(), 0, own) : IndexArgsAttr());
            rewriter.setInsertionPointAfter(group.outermost);
            idr::ReturnOp::create(rewriter, h.getLoc(), group.outermost->getResults());
            for (const idr::joins::Site &site : sites)
              idr::joins::jumpAt(rewriter, site,
                                 group.targets.tokenFor(site.target, site.op->getParentRegion()));
          },
          [&](const Continuation &k) {
            // The call that leaves for the group's entry is a site of the
            // body, which runs it and gives on what it gives.
            for (auto [i, fn] : llvm::enumerate(members))
              sitesIn(fns[fn].getBody(), static_cast<unsigned>(i), 0);
            sites.push_back(idr::joins::Site{k.call, memberOf.find(k.call.getCalleeAttr().getAttr())->second,
                                             k.call.getArgs(), k.call.getIndexArgsAttr()});
            idr::joins::wrap(rewriter, k.call, regions, sites, origin);
          });
      for (unsigned fn : members)
        rewriter.eraseOp(fns[fn]);
      ++placed;
    });
  }
  // Every call left in a moved body: its tail fact where it now stands.
  if (placed != 0)
    program.walk([&](idr::CallOp call) { call.setTail(idr::tail::decide(call)); });
  return placed;
}

struct Contify : idr::impl::IdrContifyBase<Contify> {
  void runOnProgram(idr::ProgramOp program) override {
    unsigned placed = contify(program);
    numContified += placed;
    if (placed == 0)
      return markAllAnalysesPreserved();
  }
};

} // namespace
