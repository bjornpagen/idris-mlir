// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The reading of the program as statements about its points, each numbered
// once. Every function's parameters and results are laid out by its label
// first; then one walk of the program reads each op's edges as it declares
// them (flowEdgesOf), keeps those that carry a label, and expands the
// constants' parts where they are held. Every point is normalized to its
// node (nodeOf) as it is stated: a function's parameter is its entry
// block's argument, one node; a part of a value is its anchor's node. A
// dispatch's callee and the values it moves get their nodes here too, so a
// firing reads numbers alone. A call among its function's tails, direct or
// a dispatch, states its callee's result points one set with its caller's:
// the tails are read once down from each body, since the program is read
// as the frontend wrote it, where no call's own fact says where it stands
// yet. A constant is looked into on an explicit stack, so one of any
// depth takes no recursion; so is the question of which of its parts hold
// a closure, which defunctionalization asks too.

#include "idr/Analysis/Labels.h"

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Tail.h"
#include "idr/Support/Match.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/Support/ErrorHandling.h"

#include <span>
#include <utility>
#include <variant>

using namespace mlir;

namespace idr {

namespace {

// Where a constructor stands on a walk of a constant: met, its fields not
// yet pushed; or opened, its fields done before it is popped again.
enum class Visit : std::uint8_t { Met, Opened };

} // namespace

// How a part holds closures is its own answer (closureHoldingOf); a closure
// and a constructor have theirs stored, and a part that holds none, a big
// or no constant of ours (a string, an integer, a Double), is never stored.
bool ClosureParts::answer(Attribute part) const {
  return match(
      closureHoldingOf(part), [](HoldsNoClosure) { return false; },
      [&](OneOf<AttrOf<ClosureAttr>, AttrOf<ConAttr>> auto) { return known.find(part)->second; });
}

// A closure holds itself; a constructor is answered once its fields are.
bool ClosureParts::holds(Attribute part) {
  footprint::Vector<std::pair<Attribute, Visit>> work{{part, Visit::Met}};
  while (!work.empty()) {
    auto [at, visit] = work.back();
    match(
        closureHoldingOf(at), [&](HoldsNoClosure) { work.pop_back(); },
        [&](AttrOf<ClosureAttr>) {
          known[at] = true;
          work.pop_back();
        },
        [&](AttrOf<ConAttr> held) {
          if (known.contains(at)) {
            work.pop_back();
            return;
          }
          ConAttr con = held.get();
          if (visit == Visit::Met) {
            work.back().second = Visit::Opened;
            con.walkFields([&](Attribute field, unsigned) { work.push_back({field, Visit::Met}); });
            return;
          }
          bool found = false;
          con.walkFields([&](Attribute field, unsigned) { found = found || answer(field); });
          known[at] = found;
          work.pop_back();
        });
  }
  return answer(part);
}

} // namespace idr

namespace idr::labels {

//===----------------------------------------------------------------------===//
// The reading
//===----------------------------------------------------------------------===//

namespace {

// Where a constant part is held: a value, an anchor, or a point already
// numbered (a label's parameter). Only a closure needs the node of where it
// is, so a place becomes a node only when a closure is expanded there.
using Place = std::variant<Value, FlowAnchor, Node>;

// A constant part to expand at a place, of a carrier; or the link a
// suspension's label owes once its captures are expanded.
struct Expansion {
  Attribute part;
  Place at;
  Type carrier;
};
using Pending = std::variant<Expansion, Statements::Linked>;

// The ops at each function's tails with no re-pack on the way, by the
// function's id, read once down from each body before the walk.
using TailsOf = IndexVector<solver::FunctionId, llvm::SmallVector<Operation *>>;

// One reading of a program into `out`, and the constants it has expanded,
// each once.
class Reading {
public:
  Reading(Read &out, const solver::ProgramGraph &graph, TailsOf tails)
      : out(out), graph(graph), tails(std::move(tails)) {}

  void add(Operation *op, const FlowEdges::Edge &edge);
  // Each direct call among a function's tails gives its caller's results.
  void tailCalls();

private:
  Node nodeOf(const FlowSource &point) {
    return labels::nodeOf(out.points, point, [&](const auto &key) { return out.points.of(key); });
  }
  Node nodeOf(const FlowPlace &place) {
    return labels::nodeOf(out.points, place, [&](const auto &key) { return out.points.of(key); });
  }
  Node nodeOf(const Place &place);
  void flow(Operation *op, const FlowSource &from, const FlowPlace &target, Link how);
  // `call`, a direct call among the tails of `caller`, gives its caller's
  // results: each result point of its callee that carries a label is one
  // set with its caller's.
  void tailResults(Label caller, CallOp call);
  void sink(OpOperand &use, const FlowPlace &target);
  void dispatch(CallOpInterface call);
  void moves(ValueRange values);
  void expand(Attribute part, Value at, Type carrier);
  void expandOne(const Expansion &next, footprint::Vector<Pending> &work);

  Read &out;
  const solver::ProgramGraph &graph;
  TailsOf tails;
  // The closure constants already expanded at a point, and the constructor
  // constants already laid out at their anchors.
  footprint::DenseSet<std::pair<Attribute, Node>> expanded;
  footprint::DenseSet<Attribute> laid;
  ClosureParts holding;
};

// A flow that carries no label, and what only a reference does (a fresh
// cell, a reference given up), states nothing. A source, a unification and
// a dispatch are of labels alone. A constant is looked into whatever
// carrier holds it: a constructor of any data type may hold a closure in a
// field.
void Reading::add(Operation *op, const FlowEdges::Edge &edge) {
  match(
      edge.move,
      [&](const FlowEdges::Flow &move) {
        if (!edge.carriesAny(Carriers::labels()))
          return;
        flow(op, move.from, move.to, linkOf(edge.carriers));
      },
      [&](const FlowEdges::Unify &move) {
        out.statements.links.push_back({nodeOf(move.a), nodeOf(move.b), Link::Unify});
      },
      [&](const FlowEdges::Source &move) {
        out.statements.sources.push_back({out.points.of(move.to), out.points.labelOf(move.label)});
      },
      [](const FlowEdges::Fresh &) {}, [](const FlowEdges::Release &) {},
      [](const FlowEdges::Overwrite &) {}, [](const FlowEdges::Fill &) {},
      [&](const FlowEdges::Constant &move) {
        expand(move.part, move.to, unrestricted(move.to.getType()));
      },
      [&](FlowEdges::Dispatch move) { dispatch(move.call); });
}

// The tails were found once, before the walk; a call among them is read
// from there, never asked again where it stands. Any op may stand at a
// tail, so which of them is a direct call is asked of the op.
void Reading::tailCalls() {
  for (solver::FunctionId id : graph.functions())
    for (Operation *source : tails[id])
      if (auto call = dyn_cast<CallOp>(source))
        tailResults(out.points.labelOf(graph.op(id)), call);
}

void Reading::tailResults(Label caller, CallOp call) {
  Label callee = out.points.labelOf(call.getCalleeAttr());
  for (auto [j, result] : llvm::enumerate(call->getResults()))
    if (carriesLabels(result.getType())) {
      auto index = static_cast<unsigned>(j);
      out.statements.links.push_back(
          {out.points.result(callee, index), out.points.result(caller, index), Link::Unify});
    }
}

Node Reading::nodeOf(const Place &place) {
  return match(
      place, [&](Value value) { return out.points.of(value); },
      [&](const FlowAnchor &anchor) { return out.points.of(anchor); }, [](Node node) { return node; });
}

// A flow of a whole value, which the op takes over or reads, moves it out
// of the use that holds it; the flow of a part moves no use's value, and a
// parameter or a result is no use's.
void Reading::flow(Operation *op, const FlowSource &from, const FlowPlace &target, Link how) {
  match(
      from.at, [&](FlowSource::Taken taken) { sink(*taken.use, target); },
      [&](FlowSource::Whole whole) {
        for (OpOperand &use : op->getOpOperands())
          if (use.get() == whole.value)
            sink(use, target);
      },
      [](const FlowSource::Part &) {}, [](FlowSource::Parameter) {}, [](FlowSource::Result) {});
  out.statements.links.push_back({nodeOf(from), nodeOf(target), how});
}

// A use moves its value into one place: a second edge from it joins its
// target to the first, so the use has one slot to be moved into.
void Reading::sink(OpOperand &use, const FlowPlace &target) {
  if (std::optional<FlowPlace> earlier = out.sinks.meet(use, target))
    out.statements.links.push_back({nodeOf(*earlier), nodeOf(target), Link::Unify});
}

// A dispatch's callee, the function it is in, where it stands, and the
// values it moves, each with its node, read once: every label it runs owes
// edges from these alone.
void Reading::dispatch(CallOpInterface call) {
  Operation *op = call.getOperation();
  Operation::operand_range args = call.getArgOperands();
  auto fn = op->getParentOfType<FuncOp>();
  Dispatched dispatched{out.points.of(cast<Value>(call.getCallableForCallee())),
                        out.points.labelOf(fn),
                        llvm::is_contained(tails[graph.id(fn)], op) ? Standing::Tail
                                                                     : Standing::Within,
                        static_cast<std::uint32_t>(args.size()),
                        static_cast<std::uint32_t>(out.moves.size()),
                        0,
                        0};
  moves(args);
  dispatched.firstResult = static_cast<std::uint32_t>(out.moves.size());
  moves(op->getResults());
  dispatched.end = static_cast<std::uint32_t>(out.moves.size());
  out.dispatches.push_back(dispatched);
}

// Each of `values` that carries a label, at its position, with its node and
// its link.
void Reading::moves(ValueRange values) {
  for (auto [i, value] : llvm::enumerate(values))
    if (carriesLabels(value.getType()))
      out.moves.push_back({static_cast<std::uint32_t>(i), out.points.of(value),
                           linkOf(Carriers::of(value.getType()))});
}

// A constant part held at `at`, of carrier `carrier`: a closure is its
// label there, its captures at the label's parameters; a suspension is that
// too, and its label returns into the forced state of its type; a
// constructor holds each field at its field's anchor, which is its type's
// wherever the constructor is held, so only a closure needs the point
// where it is. A shared closure at one point, and a shared constructor, is
// expanded once. The parts are expanded in the order a walk of the
// constant meets them, each part's statements before its parts'.
void Reading::expand(Attribute part, Value at, Type carrier) {
  footprint::Vector<Pending> work;
  work.push_back(Expansion{part, at, carrier});
  while (!work.empty()) {
    Pending next = std::move(work.back());
    work.pop_back();
    match(
        next, [&](const Expansion &expansion) { expandOne(expansion, work); },
        [&](const Statements::Linked &linked) { out.statements.links.push_back(linked); });
  }
}

// One part's statements, its own parts pushed to come next, the first on
// top, and a suspension's link beneath them, after its captures. A part
// that holds no closure has no statements, and `holds` has said so first.
void Reading::expandOne(const Expansion &next, footprint::Vector<Pending> &work) {
  if (!holding.holds(next.part))
    return;
  match(
      closureHoldingOf(next.part),
      [&](AttrOf<ClosureAttr> held) {
        Node at = nodeOf(next.at);
        if (!expanded.insert({next.part, at}).second)
          return;
        ClosureAttr closure = held.get();
        FlatSymbolRefAttr symbol = closure.getCallee();
        Label label = out.points.labelOf(symbol);
        out.statements.sources.push_back({at, label});
        // Which labels the carrier carries, as its type answers: a
        // suspension's label returns into its type's forced state, a
        // closure's to its callers. A closure constant is held only where
        // its carrier carries labels, which the constant's verifier holds
        // every part to (ClosureAttr::isBuildableAt).
        match(
            carryingOf(next.carrier),
            [&](const LabelCarrier &labels) {
              match(
                  labels, [](const carrying::Closure &) {},
                  [&](const carrying::Suspension &suspension) {
                    work.push_back(Statements::Linked{
                        out.points.result(label, 0),
                        out.points.of(FlowAnchor::forcedOf(suspension.type.get())), Link::Unify});
                  });
            },
            [](OneOf<carrying::Reference, carrying::Nothing> auto) {
              llvm::reportFatalInternalError(
                  "a closure constant held at a type that carries no labels, which "
                  "ClosureAttr::isBuildableAt refuses");
            });
        FuncOp fn = out.points.function(symbol);
        ArrayAttr captures = closure.getCaptures();
        for (auto index = static_cast<unsigned>(captures.size()); index-- > 0;)
          work.push_back(Expansion{captures[index], out.points.parameter(label, index),
                                   unrestricted(fn.getArgumentTypes()[index])});
      },
      [&](AttrOf<ConAttr> held) {
        ConAttr con = held.get();
        if (!laid.insert(con).second)
          return;
        DataType data = con.getData();
        Tag tag = con.getTag();
        ArrayRef<Type> fields = data.ctor(tag).fields;
        footprint::Vector<Expansion> parts;
        con.walkFields([&](Attribute field, unsigned i) {
          parts.push_back({field, FlowAnchor::fieldOf(data, tag, i), unrestricted(fields[i])});
        });
        for (Expansion &part : llvm::reverse(parts))
          work.push_back(std::move(part));
      },
      [](HoldsNoClosure) {});
}

} // namespace

Read readProgram(Operation *program, const solver::ProgramGraph &graph) {
  Read out{Points(graph), Sinks(), Statements(), {}, {}};
  TailsOf tails = graph.table<llvm::SmallVector<Operation *>>();
  for (solver::FunctionId id : graph.functions())
    tails[id] = tail::sourcesOf(graph.op(id));
  Reading reading(out, graph, std::move(tails));
  FlowEdges edges;
  program->walk([&](Operation *op) {
    flowEdgesOf(op, edges);
    for (const FlowEdges::Edge &edge : edges.edges())
      reading.add(op, edge);
    edges.clear();
  });
  reading.tailCalls();
  return out;
}

// The label takes the call's arguments after its captures and gives its
// results to the call's, and its caller's where the call is in tail
// position. A label fits the carrier of the callee that holds it, which
// the flow rule proved: it has every argument as a parameter.
void readFiring(const Read &read, Dispatch dispatch, Label label, Statements &to) {
  const Dispatched &run = read.dispatches[std::to_underlying(dispatch)];
  std::span<const Moved> moves(read.moves);
  std::span<const Moved> arguments =
      moves.subspan(run.firstArgument, run.firstResult - run.firstArgument);
  std::span<const Moved> results = moves.subspan(run.firstResult, run.end - run.firstResult);
  unsigned captures = read.points.parameters(label) - run.arguments;
  for (const Moved &arg : arguments)
    to.links.push_back({arg.node, read.points.parameter(label, captures + arg.position), arg.how});
  for (const Moved &result : results)
    to.links.push_back({read.points.result(label, result.position), result.node, result.how});
  if (run.standing == Standing::Tail)
    for (const Moved &result : results)
      to.links.push_back({read.points.result(label, result.position),
                          read.points.result(run.caller, result.position), Link::Unify});
}

} // namespace idr::labels
