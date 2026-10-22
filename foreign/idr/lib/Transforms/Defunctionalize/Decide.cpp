// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The keys: every slot's carrier and the labels the solve found for it,
// and every key the program may ask for, each given a dense id in the order
// met, which is the order every walk over the keys takes.
//
// A parameter's and a result's key are their function's, keyed once before
// anything else, so no function is read while another is rewritten; a
// part's is its anchor's, the same for every value of its kind; a value's
// is its own point's, unless the widening gave it the one key all its uses
// move it into.
//
// And the decision made whole, in its order: the program graph it reads
// rows over is the program's calls, and each run of labels the label solve
// found as a call of each label it runs.

#include "idr/Analysis/Effects.h"
#include "idr/Analysis/Labels.h"
#include "idr/IR/Families/Substitute.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Footprint.h"
#include "idr/Support/Id.h"
#include "idr/Transforms/Defunctionalize.h"
#include "idr/Transforms/Effects.h"

#include "llvm/ADT/STLExtras.h"

#include <tuple>
#include <utility>

using namespace mlir;

namespace idr::defunctionalize {

Decision::Decision(ProgramOp top, const Labels &solve, solver::ProgramGraph &calls)
    : program(top), labels(solve), graph(calls), ctx(top.getContext()), widened(solve.numPoints()),
      signatures(calls.size()) {}

Slot Decision::keyWith(Type carrier, const FlowSource &source) const {
  if (!carriesLabels(carrier))
    return std::nullopt;
  return Key{unrestricted(carrier), labels.labelsOf(source)};
}

// What every value of a kind holds at `anchor`. A capture has no slot of
// its own: a closure's parts are its label's parameters.
Slot Decision::anchorKey(const FlowAnchor &anchor) const {
  std::optional<Type> carrier = anchor.slot();
  if (!carrier || !carriesLabels(*carrier))
    return std::nullopt;
  return Key{unrestricted(*carrier), labels.labelsOf(anchor)};
}

// A value's key: its point's labels, or those the widening gave the point,
// read by the number the label solve gave it once. A value no statement
// named holds the empty set.
Slot Decision::keyOf(Value value) const {
  if (!carriesLabels(value.getType()))
    return std::nullopt;
  std::optional<labels::Node> node = labels.nodeOf(value);
  ArrayAttr wide = node ? widened[std::to_underlying(*node)] : ArrayAttr();
  return Key{unrestricted(value.getType()), wide ? wide : labels.labelsAt(node)};
}

Slot Decision::sinkOf(OpOperand &use) const {
  std::optional<FlowPlace> sink = labels.sinkOf(use);
  if (!sink)
    return std::nullopt;
  return idr::match(
      sink->at, [&](FlowSource::Whole whole) { return keyOf(whole.value); },
      [&](const FlowPlace::Part &part) { return anchorKey(part.anchor); },
      [&](FlowSource::Parameter param) {
        return signature(graph.id(param.function)).arguments[param.index];
      },
      [&](FlowSource::Result result) {
        return signature(graph.id(result.function)).results[result.index];
      });
}

// Each key of `slots`, then each key `types` hold, and every key each
// leads to, given its id once, in the order met: after a lazy key, its
// forced state, which its family's `forced` field holds, then the keys its
// value's type holds. A stack, never a recursion: a suspension's forced
// state may hold a suspension in turn, as deeply as the program's types
// nest. The next key to meet is on top, so the keys are met in the order a
// depth-first walk meets them.
void Decision::note(ArrayRef<Slot> slots, ArrayRef<Type> types) {
  SmallVector<Slot> pending;
  auto push = [&](ArrayRef<Slot> keys, ArrayRef<Type> holders) {
    SmallVector<Slot> next(keys);
    for (Type type : holders)
      slotsIn(type, next);
    pending.append(next.rbegin(), next.rend());
  };
  push(slots, types);
  while (!pending.empty()) {
    Slot slot = pending.pop_back_val();
    if (!slot || !ids.try_emplace(*slot, static_cast<KeyId>(families.size())).second)
      continue;
    families.push_back(Family{*slot, DataType(), DataType(), Dispatcher{}});
    if (carrierOf(*slot) == Carrier::Lazy) {
      auto lazy = cast<LazyType>(slot->carrier);
      push({anchorKey(FlowAnchor::forcedOf(lazy))}, {lazy.getValue()});
    }
  }
}

// The slots a type holds that are no value's, in the walk's order: the
// fields of each data family met in it, a closure's signature included,
// and the elements of each shaped type.
void Decision::slotsIn(Type type, SmallVectorImpl<Slot> &out) const {
  AttrTypeWalker walker;
  walker.addWalk([&](DataType data) {
    for (Tag tag : data.possibleTags())
      if (std::optional<SmallVector<Type>> fields = data.determinedFields(tag))
        for (auto [i, field] : llvm::enumerate(*fields))
          if (carriesLabels(field))
            out.push_back(anchorKey(FlowAnchor::fieldOf(data, tag, static_cast<unsigned>(i))));
  });
  walker.addWalk([&](ShapedType shaped) {
    if (carriesLabels(shaped.getElementType()))
      out.push_back(anchorKey(FlowAnchor::elementsOf(shaped.getElementType())));
  });
  walker.walk(type);
}

// A closure, suspension or constant whose every use moves it into slots of
// one key with its labels and more takes that key, so no coercion follows
// it. Read off each op's flow: what makes a carrier value is an edge's
// source, which the op's flow interface declares, and the label solve
// named it there, so its point has a number.
void Decision::widen() {
  FlowEdges edges;
  program.walk([&](FlowOpInterface flow) {
    Operation *op = flow.getOperation();
    if (op->getNumResults() != 1 || !carriesLabels(op->getResult(0).getType()))
      return;
    Value value = op->getResult(0);
    edges.clear();
    flow.getFlowEdges(edges);
    bool builds = llvm::any_of(edges.edges(), [&](const FlowEdges::Edge &edge) {
      return idr::match(
          edge.move, [&](const FlowEdges::Source &source) { return source.to == value; },
          [&](const FlowEdges::Constant &constant) { return constant.to == value; },
          [](const OneOf<FlowEdges::Flow, FlowEdges::Unify, FlowEdges::Fresh, FlowEdges::Release,
                         FlowEdges::Overwrite, FlowEdges::Fill, FlowEdges::Dispatch> auto &) {
            return false;
          });
    });
    if (!builds)
      return;
    Slot common;
    for (OpOperand &use : value.getUses()) {
      Slot to = sinkOf(use);
      if (!to || (common && *common != *to))
        return;
      common = to;
    }
    Slot own = keyOf(value);
    if (common && own && common->carrier == own->carrier &&
        labels::within(own->labels, common->labels))
      widened[std::to_underlying(*labels.nodeOf(value))] = common->labels;
  });
}

// Each function's calls, and in its row beside them each label it runs,
// with how many of its runs run it. A run is no call yet: the call an
// apply's case makes takes its tail fact from the one definition where it
// stands, once the program is first order, and a force becomes a call of
// its dispatch function, not of the label. A row holds only calls, so a run
// stands as a call within, which the atoms' join never reads and the
// rewrite's calls replace; the row stays in the graph's one order, a
// (callee, kind) once, merged with a direct call of the same label.
void Decision::complete(
    IndexVector<solver::FunctionId, footprint::Vector<solver::FunctionId>> &ran) {
  Count<solver::FunctionId> space = ran.size();
  solver::Editor editor = graph.thaw();
  for (solver::FunctionId f : space.ids()) {
    footprint::Vector<solver::FunctionId> &labelled = ran[f];
    if (labelled.empty())
      continue;
    llvm::sort(labelled);
    std::span<const solver::Call> direct = editor.callees(f);
    llvm::SmallVector<solver::Call, 4> row;
    std::size_t next = 0;
    for (std::size_t from = 0; from < labelled.size();) {
      solver::FunctionId label = labelled[from];
      std::size_t to = from;
      while (to < labelled.size() && labelled[to] == label)
        ++to;
      auto sites = static_cast<std::uint32_t>(to - from);
      from = to;
      while (next < direct.size() && std::tuple(direct[next].callee, direct[next].kind) <
                                         std::tuple(label, TailKind::nontail))
        row.push_back(direct[next++]);
      if (next < direct.size() && direct[next].callee == label &&
          direct[next].kind == TailKind::nontail)
        sites += direct[next++].sites;
      row.push_back({label, TailKind::nontail, sites});
    }
    row.append(direct.begin() + static_cast<std::ptrdiff_t>(next), direct.end());
    editor.setCallees(f, row);
  }
  std::move(editor).freeze();
}

namespace {

// The decision's reader of a body for the atoms' join: a call adds nothing
// of its own, nor does a run of labels, since the graph holds both as
// calls, whose callees' rows the join gives.
struct ByGraph {
  void call(CallOp, rows::Fold &, rows::Runs) {}
  rows::Read other(Operation *op, rows::Fold &, rows::Runs) {
    return isa<RunsLabelsOpInterface>(op) ? rows::Read::ByReader : rows::Read::ByDeclaration;
  }
};

} // namespace

FailureOr<std::unique_ptr<Decision>> Decision::decide(ProgramOp program, const Labels &labels,
                                                      solver::ProgramGraph &graph,
                                                      solver::Work &work) {
  std::unique_ptr<Decision> decision(new Decision(program, labels, graph));
  Decision &d = *decision;
  // Every signature first, which every other key of a parameter or a
  // result reads; then the widening, which reads the sinks; then every key
  // the program's values and types ask for, and the labels each run runs,
  // read in the same walk.
  for (FuncOp fn : program.getOps<FuncOp>()) {
    Signature &sig = d.signatures[graph.id(fn)];
    for (BlockArgument arg : fn.getArguments())
      sig.arguments.push_back(d.keyWith(arg.getType(), FlowSource::of(Value(arg))));
    auto name = FlatSymbolRefAttr::get(fn.getSymNameAttr());
    for (auto [j, type] : llvm::enumerate(fn.getResultTypes()))
      sig.results.push_back(d.keyWith(type, FlowSource::result(name, static_cast<unsigned>(j))));
  }
  d.widen();
  IndexVector<solver::FunctionId, footprint::Vector<solver::FunctionId>> ran(graph.size());
  for (FuncOp fn : program.getOps<FuncOp>()) {
    solver::FunctionId self = graph.id(fn);
    const Signature &sig = d.signature(self);
    FunctionType type = fn.getFunctionType();
    d.note(llvm::to_vector(llvm::concat<const Slot>(sig.arguments, sig.results)),
           llvm::to_vector(llvm::concat<const Type>(type.getInputs(), type.getResults())));
    fn.walk([&](Operation *op) {
      if (auto runner = dyn_cast<RunsLabelsOpInterface>(op))
        for (auto label : labels.runs(runner).getAsRange<FlatSymbolRefAttr>())
          ran[self].push_back(graph.id(label));
      for (Value result : op->getResults())
        d.note({d.keyOf(result)}, {result.getType()});
      for (Region &region : op->getRegions())
        for (Block &block : region)
          for (Value arg : block.getArguments())
            d.note({d.keyOf(arg)}, {arg.getType()});
    });
    if (!ran[self].empty())
      d.running.push_back({self, fn});
  }
  // Each label's row, before any type changes: every function's own atoms
  // joined over the graph its runs completed, callees first.
  d.complete(ran);
  IndexVector<solver::FunctionId, effects::Row> atoms =
      rows::solveAtoms(graph, ByGraph{}, *d.ctx, work);
  if (failed(d.declare(atoms)))
    return failure();
  d.convertSignatures();
  // The functions the program had, whose edits the decision reads: each
  // dispatch function it adds is born rewritten.
  auto held = program.getOps<FuncOp>();
  footprint::Vector<FuncOp> functions(held.begin(), held.end());
  // Each memo family's dispatch function, and how a force calls it: at the
  // cell's indices, the index terms its key's carrier names, which every
  // slot of the key holds.
  for (Family &family : d.families) {
    if (carrierOf(family.key) != Carrier::Lazy)
      continue;
    FailureOr<FuncOp> force = d.defineForce(family);
    if (failed(force))
      return failure();
    auto indices = IndexArgsAttr::get(d.ctx, family.at.getIndices(),
                                      family.at.getGroup().indices(family.at.getMember()).size());
    FunctionType at =
        families::substitute(force->getFunctionType(), force->getExtentsAttr(), indices);
    family.force = Dispatcher{*force, FlatSymbolRefAttr::get(force->getSymNameAttr()), indices,
                              at.getInput(0), at.getResult(0)};
    d.made.push_back(*force);
  }
  // Each function's edits, in the program's order, every type and
  // attribute they build made here.
  d.poisoned = ub::PoisonAttr::get(d.ctx);
  for (FuncOp fn : functions) {
    FailureOr<Edits> edits = d.plan(fn);
    if (failed(edits))
      return failure();
    d.planned.push_back(std::move(*edits));
  }
  return decision;
}

} // namespace idr::defunctionalize
