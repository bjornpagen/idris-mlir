// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What exclusivity's solve reads of a body, once, before any context is
// solved (ExclusivityDetail.h): its followed values numbered by the walk,
// the edges along which sharing moves between them, the values shared in
// every context, its calls and its return, the views it takes a reference
// of, its moves into memo labels' fields and the parts it moves or reads
// out of them. Every edge is read off the flow interface and upstream's
// region interfaces, each op's edges enumerated once.
//
// A block that ends where control never leaves back to its parent (a
// crash, an exit, ub.unreachable) forwards nothing, so it gives the
// region's successors nothing: a match with a crash case yields what its
// other cases yield. Every terminator is one of that, a region branch
// terminator, a return or a jump, which forward through forwardedValues; a
// terminator with block successors cannot stand in a function before the
// lowering, and meeting one is an internal error naming it.
#include "idr/Analysis/Ownership/ExclusivityDetail.h"

#include "idr/Analysis/Ownership/Facts.h"
#include "idr/Analysis/Ownership/Walks.h"
#include "idr/Analysis/Solver/Extraction.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/Support/Match.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/Support/ErrorHandling.h"
#include "llvm/Support/raw_ostream.h"

#include <optional>
#include <string>

using namespace mlir;

namespace idr::detail::exclusivity {

namespace {

// Whether `type` is a memo family's: its cells change while references to
// them live, so what a field holds is the label's, not the cell value's.
bool memoFamily(Type type) { return ownership::isMemo(ownership::familyOf(type)); }

// A value of the body being read, by its place in the solver's walk.
struct BodyValueTag {
  using Minter = solver::Numbering<BodyValueTag>;
};
using BodyValue = Id<BodyValueTag>;

// The reading of one body. Its one map, from a value to its number, is the
// solver's numbering: it lives while the body is read and goes with it, and
// what the reading keeps of each value is in tables by that number.
class Reader {
public:
  Reader(FuncOp fn, const solver::ProgramGraph &graph, Anchors &anchors)
      : fn(fn), entry(&fn.getBody().front()), graph(graph), anchors(anchors), numbering(fn),
        localAt(numbering.size(), noLocal), firstForward(numbering.size()),
        partOf(numbering.size()) {}

  Body read() {
    body.fn = fn;
    idr::exclusivity::forEachFollowed(fn, [&](Value value, std::uint32_t at) {
      localAt[numbering.at(value)] = at;
      body.values = at + 1;
    });
    explained.emplace(idr::exclusivity::FollowedNumbers::count(body.values));
    for (BlockArgument param : entry->getArguments()) {
      body.params.push_back(localOf(param));
      explain(param);
    }
    // Each region argument's sources, read once: what forwardedValues says
    // every op of the body forwards into it.
    fn.walk([&](Operation *op) {
      forwardedValues(op, [&](OpOperand &operand, Value input) {
        if (auto arg = dyn_cast<BlockArgument>(input))
          if (!firstForward[numbering.at(arg)])
            firstForward[numbering.at(arg)] = operand.get();
      });
    });
    fn.walk([&](Operation *op) {
      if (op->hasTrait<mlir::OpTrait::IsTerminator>() && op->getNumSuccessors() != 0)
        successorsBeforeLowering(op);
      readOp(op);
    });
    ownership::forEachCall(fn, [&](FunctionCallOpInterface call) { readCall(call); });
    readReturn();
    // Roots are read once every part read of the body is known.
    for (Value value : copiedValues)
      if (std::optional<ViewRoot> root = rootOf(value)) {
        if (root->kind == ViewRoot::Kind::Value)
          body.seeds.push_back(root->index);
        else
          body.viewsCopied.push_back(*root);
      }
    // A value no declared flow explains is shared: a result of an op that
    // declares none, an input no predecessor forwards, an argument of a
    // region no interface says.
    for (std::uint32_t at = 0; at != body.values; ++at)
      if (!explained->test(idr::exclusivity::FollowedNumbers::at(at)))
        body.seeds.push_back(at);
    return std::move(body);
  }

private:
  // No region holds a terminator with block successors before the
  // lowering, so meeting one is the compiler's bug, never the program's.
  [[noreturn]] static void successorsBeforeLowering(Operation *op) {
    std::string text;
    llvm::raw_string_ostream out(text);
    out << "internal error: exclusivity meets a terminator with block successors before the "
           "lowering; at "
        << op->getName() << " (" << op->getLoc() << ")";
    llvm::reportFatalInternalError(llvm::Twine(text));
  }

  Local localOf(Value value) const { return localAt[numbering.at(value)]; }

  void explain(Value value) {
    if (Local at = localOf(value); at != noLocal)
      (void)explained->raise(idr::exclusivity::FollowedNumbers::at(at));
  }

  void edge(Local from, Local to) {
    if (from != noLocal && to != noLocal)
      body.edges.push_back({from, to});
  }

  void seed(Value value) {
    if (Local at = localOf(value); at != noLocal)
      body.seeds.push_back(at);
  }

  // Whether a value exclusivity does not follow still keeps its cells
  // unshared: it reaches no cell (an atom, a word), or its grade claims
  // `unique deep`. Static data is shared by definition, and a view is not
  // its own.
  static bool exclusiveByType(Value value) {
    return !holdsReferences(value.getType()) || claims(value.getType(), Unique::Deep);
  }

  // `from` moves into `to`: sharing follows it, and a value whose type
  // answers gives what its type says.
  void move(Value from, Value to) {
    if (Local at = localOf(from); at != noLocal)
      edge(at, localOf(to));
    else if (!exclusiveByType(from))
      seed(to);
  }

  // A reference is taken of `value` without its own given up (a copy of a
  // value read): the cell it is, or the owner it views, is shared from then
  // on, and so is the copy. Its root is read once the body is.
  void copied(Value value) { copiedValues.push_back(value); }

  // Where a value was lent from: up through the positions that hand a value
  // on as itself, the parts it was read from and the region entries that
  // forward it, to a followed value of the body or to one of the body's
  // parameters. None for static data or a value no view of which is a
  // reference counted here.
  std::optional<ViewRoot> rootOf(Value value) const {
    for (Value at = value;;) {
      if (Local here = localOf(at); here != noLocal)
        return ViewRoot{ViewRoot::Kind::Value, here};
      if (auto arg = dyn_cast<BlockArgument>(at)) {
        if (arg.getOwner() == entry)
          return ViewRoot{ViewRoot::Kind::Parameter, arg.getArgNumber()};
        std::optional<Value> source = firstForward[numbering.at(arg)];
        if (!source)
          return std::nullopt;
        at = *source;
        continue;
      }
      if (std::optional<Value> same = ownership::sameValueSource(at)) {
        at = *same;
        continue;
      }
      if (std::optional<Value> whole = partOf[numbering.at(at)]) {
        at = *whole;
        continue;
      }
      return std::nullopt;
    }
  }

  void readOp(Operation *op) {
    // A call's moves are its callee's parameters and results, read with
    // the callee's context (readCall).
    if (isa<CallOpInterface>(op))
      return;
    // An op that keeps its operand's value is that value: what shares
    // either shares both. Each side is followed at its own grade, so a
    // result that forgets its operand's claim is proved exclusive only where
    // nothing copies it, and one kept bare (an op of upstream's reads it)
    // shares its operand.
    if (op->hasTrait<SameValue>()) {
      Value operand = op->getOperand(0);
      for (Value result : op->getResults()) {
        move(operand, result);
        move(result, operand);
        explain(result);
      }
      return;
    }
    if (!declaresFlow(op))
      return;
    FlowEdges edges;
    flowEdgesOf(op, edges);
    for (const FlowEdges::Edge &edge : edges.edges())
      if (edge.carries(Carrier::Reference))
        match(
            edge.move, [&](const FlowEdges::Flow &flow) { readFlow(flow, edges); },
            [&](const FlowEdges::Fresh &fresh) { explain(fresh.to); },
            [&](const FlowEdges::Constant &constant) {
              explain(constant.to);
              seed(constant.to);
            },
            [](const FlowEdges::Unify &) {}, [](const FlowEdges::Source &) {},
            [](const FlowEdges::Release &) {}, [](const FlowEdges::Overwrite &) {},
            [](const FlowEdges::Fill &) {},
            [](const FlowEdges::Dispatch &) {});
  }

  // A flow among `edges`, the edges of the op that declares it.
  void readFlow(const FlowEdges::Flow &flow, const FlowEdges &edges) {
    match(
        flow.to.at,
        // Into a value whole, which that explains.
        [&](const FlowSource::Whole &into) {
          explain(into.value);
          readInto(flow.from, into.value, edges);
        },
        // Into a part of a value: the value holds what moves in, a memo
        // label's field the label. What fills every slot of the part (an
        // array's fill) is reached once per slot, so the value reaches it
        // more than once and is shared in every context, as the local rule
        // bounds it.
        [&](const FlowPlace::Part &part) {
          std::optional<FlowAnchor::Field> field = ownership::fieldOf(part.anchor);
          if (field && memoFamily(part.of.getType()))
            return intoAnchor(flow.from, anchors.of(*field));
          if (flow.fills == FlowEdges::Fills::EverySlot)
            return seed(part.of);
          readInto(flow.from, part.of, edges);
        },
        // A parameter or a result: the call's and the return's own reading.
        [](const FlowSource::Parameter &) {}, [](const FlowSource::Result &) {});
  }

  // What `from` brings `to`, among the edges of the op: a use taken over
  // moves its sharing; a value read and not given up is copied, which
  // shares both; a part taken out of a value moves that value's sharing; a
  // part of a memo label's field brings what the field holds; a part read
  // is a view, a reference of its own only when the op takes one.
  void readInto(const FlowSource &from, Value to, const FlowEdges &edges) {
    match(
        from.at, [&](const FlowSource::Taken &taken) { move(taken.use->get(), to); },
        [&](const FlowSource::Whole &read) {
          if (!holdsReferences(read.value.getType()))
            return;
          copied(read.value);
          seed(to);
        },
        [&](const FlowSource::Part &part) {
          Value of = *from.value();
          std::optional<FlowAnchor::Field> field = ownership::fieldOf(part.anchor);
          if (field && memoFamily(of.getType()))
            return outOfAnchor(ownership::placeAfter(edges, part), anchors.of(*field), to);
          if (ownership::reachOf(part) == ownership::Reach::Taken)
            return move(of, to);
          if (!partOf[numbering.at(to)])
            partOf[numbering.at(to)] = of;
          // A counted value read out is a reference of its own, which its
          // type says whether or not the solve follows it (an op of
          // upstream's may read it, or have read it out of an array), so
          // what it was read from is shared from then on.
          if (ownership::leavesOpen(to.getType(), Unique::Deep)) {
            copied(of);
            seed(to);
          }
        },
        [&](const FlowSource::Parameter &) { seed(to); },
        [&](const FlowSource::Result &) { seed(to); });
  }

  void intoAnchor(const FlowSource &from, Anchor anchor) {
    std::optional<OpOperand *> taken = from.taken();
    Value value = *from.value();
    if (taken && localOf(value) != noLocal)
      body.intoAnchors.push_back({localOf(value), anchor});
    else if (!exclusiveByType(value))
      anchors.share(anchor);
  }

  // A part of a memo label's field holds what the field holds, whatever
  // else holds the cell, so it is linked to the field either way. Moved out,
  // its place emptied, the move explains the value it moves into. Read with
  // the field keeping its reference, and used, a second reference to what
  // the field holds may be taken there: the field is shared, and through
  // the link the value read with it.
  void outOfAnchor(ownership::PlaceAfter place, Anchor anchor, Value to) {
    if (Local at = localOf(to); at != noLocal)
      body.outOfAnchors.push_back({anchor, at});
    switch (place) {
    case ownership::PlaceAfter::Emptied:
      explain(to);
      return;
    case ownership::PlaceAfter::Kept:
      if (!to.use_empty())
        anchors.share(anchor);
      return;
    }
  }

  void readCall(FunctionCallOpInterface call) {
    Call out{graph.id(call.getCalleeAttr()), {}, {}, {}};
    for (auto [index, arg] : llvm::enumerate(call.getArgs())) {
      out.args.push_back(localOf(arg));
      // A view passed on: if the callee takes a reference of it, its owner
      // here is shared.
      if (localOf(arg) == noLocal && holdsReferences(arg.getType()) && !exclusiveByType(arg))
        if (std::optional<ViewRoot> root = rootOf(arg))
          out.views.push_back({static_cast<unsigned>(index), *root});
    }
    for (Value result : call->getResults()) {
      out.results.push_back(localOf(result));
      explain(result);
    }
    body.calls.push_back(std::move(out));
  }

  // What the body gives back: for each operand of its return, the followed
  // value, or what its type says; nothing for a body that never returns.
  void readReturn() {
    auto ret = dyn_cast_or_null<ReturnOp>(entry->getTerminator());
    if (!ret)
      return;
    body.returns.emplace();
    for (Value operand : ret.getOperands())
      body.returns->push_back(returned(operand));
  }

  Returned returned(Value operand) const {
    if (Local at = localOf(operand); at != noLocal)
      return at;
    return exclusiveByType(operand) ? ByType::Exclusive : ByType::Shared;
  }

  FuncOp fn;
  // The body's one block, whose arguments are its parameters.
  Block *entry;
  const solver::ProgramGraph &graph;
  Anchors &anchors;
  Body body;
  solver::Numbering<BodyValueTag> numbering;
  // Each value's number among the followed values, the first value each
  // region argument is forwarded, and the value each view read out of a
  // part is a part of.
  IndexVector<BodyValue, Local> localAt;
  IndexVector<BodyValue, std::optional<Value>> firstForward;
  IndexVector<BodyValue, std::optional<Value>> partOf;
  SmallVector<Value> copiedValues;
  // The followed values some declared flow explains, sized once the walk
  // has numbered them.
  std::optional<BitSet<idr::exclusivity::Followed>> explained;
};

} // namespace

Anchor Anchors::of(const FlowAnchor::Field &field) {
  auto [it, fresh] = keys.try_emplace(Key{field.group, field.member,
                                          static_cast<std::uint32_t>(field.ctor),
                                          static_cast<std::uint32_t>(field.index)},
                                      static_cast<Anchor>(keys.size()));
  return it->second;
}

Body readBody(FuncOp fn, const solver::ProgramGraph &graph, Anchors &anchors) {
  return Reader(fn, graph, anchors).read();
}

// Static data is no one's to take apart, so a label static data holds a
// cell of has static captures, shared whatever an init moves in.
void shareStaticAnchors(ProgramOp program, Anchors &anchors) {
  program.walk([&](ConstantOp constant) {
    constant.getValue().walk([&](ConAttr con) {
      DataType data = con.getData();
      if (!ownership::isMemo(data) || !data.labelMode(con.getTag()))
        return;
      for (unsigned index = 0, e = static_cast<unsigned>(con.getFields().size()); index != e;
           ++index)
        anchors.share(anchors.of(
            FlowAnchor::Field{data.getGroup(), data.getMember(), con.getTag(), index}));
    });
  });
}

} // namespace idr::detail::exclusivity
