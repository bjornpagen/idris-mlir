// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The one construction of join points (Joins.h): the shape from the jump
// graph, the group's ops, its members moved in, and sites made jumps. What
// it keeps per member or per jump is sized by the group, which may be most
// of the program's functions, so it lives in the footprint's vectors.

#include "idr/Transforms/Joins.h"

#include "idr/Support/Footprint.h"

#include "mlir/IR/BuiltinTypes.h"

#include <cstdint>
#include <numeric>
#include <optional>

using namespace mlir;

namespace idr::joins {

// What fills a group's tokens, which Targets keeps private.
struct Builder {
  static void place(Targets &targets, unsigned member, Operation *op, unsigned index) {
    targets.ops[member] = op;
    targets.indices[member] = index;
  }
  static void reserve(Targets &targets, unsigned members) {
    targets.ops.assign(members, nullptr);
    targets.indices.assign(members, 0);
  }
};

namespace {

// Each member's depth in an acyclic jump graph: 0 for a member that jumps
// to none, else one more than the deepest member it jumps to; none when the
// graph has a cycle. One iterative depth-first walk (no recursion on the
// group's size): a member's depth is final when it finishes, and goes to
// the member below it on the stack, which jumps to it.
std::optional<footprint::Vector<unsigned>> depthsOf(unsigned members, ArrayRef<Edge> edges) {
  // The edges out of each member, as compressed rows.
  footprint::Vector<unsigned> start(members + 1, 0);
  for (Edge edge : edges)
    ++start[edge.from + 1];
  for (unsigned m = 0; m < members; ++m)
    start[m + 1] += start[m];
  footprint::Vector<unsigned> next(start.begin(), start.end() - 1);
  footprint::Vector<unsigned> to(edges.size());
  for (Edge edge : edges)
    to[next[edge.from]++] = edge.to;

  enum class Visit : std::uint8_t { New, Open, Done };
  footprint::Vector<Visit> state(members, Visit::New);
  footprint::Vector<unsigned> depth(members, 0);
  // A frame: a member and the next of its edges to follow.
  footprint::Vector<std::pair<unsigned, unsigned>> stack;
  for (unsigned root = 0; root < members; ++root) {
    if (state[root] != Visit::New)
      continue;
    state[root] = Visit::Open;
    stack.emplace_back(root, start[root]);
    while (!stack.empty()) {
      auto &[member, edge] = stack.back();
      if (edge == start[member + 1]) {
        unsigned done = member;
        state[done] = Visit::Done;
        stack.pop_back();
        if (!stack.empty())
          depth[stack.back().first] = std::max(depth[stack.back().first], depth[done] + 1);
        continue;
      }
      unsigned target = to[edge++];
      if (state[target] == Visit::Open)
        return std::nullopt;
      if (state[target] == Visit::Done) {
        depth[member] = std::max(depth[member], depth[target] + 1);
        continue;
      }
      state[target] = Visit::Open;
      stack.emplace_back(target, start[target]);
    }
  }
  return depth;
}

// One op of the family `Group`: its results, its join regions' binders,
// its body and `regions` join regions, all empty.
template <typename Group>
Operation *makeOp(RewriterBase &rewriter, Location loc, TypeRange results,
                  ArrayRef<Attribute> binders) {
  OperationState state(loc, Group::getOperationName());
  state.addTypes(results);
  state.getOrAddProperties<typename Group::Properties>().binders =
      rewriter.getArrayAttr(binders);
  for (size_t region = 0; region <= binders.size(); ++region)
    state.addRegion();
  return rewriter.create(state);
}

// Moves `member`'s region into `into`, a join region of `op`, after the
// `tokens` an idr.loop's regions begin with; its types name its binders at
// the group's depth `scope`; its idr.return becomes the group's yield.
void moveMember(RewriterBase &rewriter, const Member &member, Region &into, unsigned tokens,
                unsigned scope) {
  rewriter.inlineRegionBefore(*member.body, into, into.end());
  Block &entry = into.front();
  Type token = rewriter.getType<TokenType>();
  for (unsigned i = 0; i < tokens; ++i)
    entry.insertArgument(i, token, into.getParentOp()->getLoc());
  unsigned binders = static_cast<unsigned>(member.binders.getSorts().size());
  if (binders && member.firstLevel != scope)
    families::renumber(into, member.firstLevel, binders, scope);
  if (auto ret = dyn_cast<ReturnOp>(entry.getTerminator())) {
    rewriter.setInsertionPoint(ret);
    rewriter.replaceOpWithNewOp<YieldOp>(ret, ret.getOperands());
  }
}

} // namespace

// The region of the member's op around `in`: an idr.loop's region holds
// its own tokens; for an idr.join it is the body, since a jump to one of its
// members comes from inside its body.
Value Targets::tokenFor(unsigned member, Region *in) const {
  Operation *op = ops[member];
  for (Region &region : op->getRegions())
    if (region.isAncestor(in))
      return cast<JoinPointsOpInterface>(op).getTokens(region)[indices[member]];
  return cast<JoinPointsOpInterface>(op).getTokens(op->getRegion(0))[indices[member]];
}

unsigned scopeDepth(Region *region) {
  unsigned depth = 0;
  for (; region; region = region->getParentRegion())
    if (auto binder = dyn_cast<ErasedBinderOpInterface>(region->getParentOp()))
      depth += static_cast<unsigned>(binder.getBoundSorts(*region).size());
  return depth;
}

Group build(RewriterBase &rewriter, Location loc, TypeRange results, ArrayRef<Member> members,
            ArrayRef<Edge> edges) {
  unsigned count = static_cast<unsigned>(members.size());
  unsigned scope = scopeDepth(rewriter.getInsertionBlock()->getParent());
  std::optional<footprint::Vector<unsigned>> depths = depthsOf(count, edges);
  // The ops, outermost first, each with its members: one idr.loop holding
  // every member, or one idr.join per depth, the members jumped to outward,
  // so each join region sees the tokens of every member it jumps to. The
  // members of level d are the run of `order` from `first[d]` to
  // `first[d + 1]`, in member order.
  unsigned levels = depths ? *llvm::max_element(*depths) + 1 : 1;
  footprint::Vector<unsigned> first(levels + 1, 0);
  footprint::Vector<unsigned> order(count);
  if (depths) {
    for (unsigned d : *depths)
      ++first[d + 1];
    for (unsigned d = 0; d < levels; ++d)
      first[d + 1] += first[d];
    footprint::Vector<unsigned> next(first.begin(), first.end() - 1);
    for (unsigned m = 0; m < count; ++m)
      order[next[(*depths)[m]]++] = m;
  } else {
    first[1] = count;
    std::iota(order.begin(), order.end(), 0u);
  }

  Group group{nullptr, nullptr, Targets()};
  Builder::reserve(group.targets, count);
  Type token = rewriter.getType<TokenType>();
  for (unsigned d = 0; d < levels; ++d) {
    ArrayRef<unsigned> level(order.data() + first[d], first[d + 1] - first[d]);
    SmallVector<Attribute> binders =
        llvm::map_to_vector(level, [&](unsigned m) -> Attribute { return members[m].binders; });
    Operation *op = depths ? makeOp<JoinOp>(rewriter, loc, results, binders)
                           : makeOp<LoopOp>(rewriter, loc, results, binders);
    if (group.body)
      YieldOp::create(rewriter, loc, op->getResults());
    else
      group.outermost = op;
    unsigned tokens = static_cast<unsigned>(level.size());
    Block *body = rewriter.createBlock(&op->getRegion(0), {}, SmallVector<Type>(tokens, token),
                                       SmallVector<Location>(tokens, loc));
    for (auto [index, m] : llvm::enumerate(level)) {
      Builder::place(group.targets, m, op, static_cast<unsigned>(index));
      Region &into = op->getRegion(static_cast<unsigned>(index) + 1);
      moveMember(rewriter, members[m], into, depths ? 0 : tokens, scope);
    }
    group.body = body;
    rewriter.setInsertionPointToEnd(body);
  }
  return group;
}

JumpOp jumpAt(RewriterBase &rewriter, const Site &site, Value token) {
  Operation *passed = site.op->getBlock()->getTerminator();
  rewriter.setInsertionPoint(passed);
  auto jump = JumpOp::create(rewriter, site.op->getLoc(), token, site.args, site.terms);
  rewriter.eraseOp(passed);
  rewriter.eraseOp(site.op);
  return jump;
}

namespace {

// The jump graph of `sites`: an edge from each member whose region holds a
// site to the member it targets; a site in the body is none.
footprint::Vector<Edge> edgesOf(ArrayRef<Member> members, ArrayRef<Site> sites) {
  footprint::Vector<Edge> edges;
  for (const Site &site : sites)
    for (auto [index, member] : llvm::enumerate(members))
      if (member.body->isAncestor(site.op->getParentRegion()))
        edges.push_back({static_cast<unsigned>(index), site.target});
  return edges;
}

void jumpAll(RewriterBase &rewriter, const Targets &targets, ArrayRef<Site> sites) {
  for (const Site &site : sites)
    jumpAt(rewriter, site, targets.tokenFor(site.target, site.op->getParentRegion()));
}

} // namespace

Operation *wrap(RewriterBase &rewriter, Operation *place, ArrayRef<Member> members,
                ArrayRef<Site> sites) {
  OpBuilder::InsertionGuard guard(rewriter);
  footprint::Vector<Edge> edges = edgesOf(members, sites);
  rewriter.setInsertionPoint(place);
  Group group = build(rewriter, place->getLoc(), place->getResultTypes(), members, edges);
  rewriter.replaceAllUsesWith(place->getResults(), group.outermost->getResults());
  rewriter.moveOpBefore(place, group.body, group.body->end());
  rewriter.setInsertionPointToEnd(group.body);
  YieldOp::create(rewriter, place->getLoc(), place->getResults());
  jumpAll(rewriter, group.targets, sites);
  return group.outermost;
}

LoopOp loopSelf(RewriterBase &rewriter, FuncOp fn, ArrayRef<Site> calls) {
  OpBuilder::InsertionGuard guard(rewriter);
  Region &body = fn.getBody();
  Block *old = &body.front();
  ArrayRef<families::Sort> sorts =
      cast<ErasedBinderOpInterface>(fn.getOperation()).getBoundSorts(body);
  unsigned own = static_cast<unsigned>(sorts.size());
  auto binders = IndexBindersAttr::get(fn.getContext(), sorts);
  // The function's new body takes its parameters; the old one moves into a
  // region of its own, which becomes the loop's one join region.
  Block *entry = rewriter.createBlock(
      &body, body.end(), old->getArgumentTypes(),
      llvm::map_to_vector(old->getArguments(), [](BlockArgument arg) { return arg.getLoc(); }));
  Region moved;
  rewriter.moveBlockBefore(old, &moved, moved.end());
  footprint::Vector<Edge> edges(calls.size(), Edge{0, 0});
  Member member{&moved, binders, /*firstLevel=*/0};
  rewriter.setInsertionPointToEnd(entry);
  Group group = build(rewriter, fn.getLoc(), fn.getFunctionType().getResults(), member, edges);
  // The body enters with the parameters and the function's own index
  // variables.
  IndexArgsAttr levels =
      own ? families::levelArgs(fn.getContext(), 0, own) : IndexArgsAttr();
  JumpOp::create(rewriter, fn.getLoc(), group.targets.tokenFor(0, group.body->getParent()),
                 entry->getArguments(), levels);
  rewriter.setInsertionPointAfter(group.outermost);
  ReturnOp::create(rewriter, fn.getLoc(), group.outermost->getResults());
  jumpAll(rewriter, group.targets, calls);
  return cast<LoopOp>(group.outermost);
}

} // namespace idr::joins
