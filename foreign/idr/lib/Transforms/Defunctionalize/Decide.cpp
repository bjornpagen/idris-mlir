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
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Footprint.h"
#include "idr/Support/Id.h"
#include "idr/Transforms/Defunctionalize.h"
#include "idr/Transforms/Effects.h"

#include "llvm/ADT/STLExtras.h"

#include <tuple>

using namespace mlir;

namespace idr::defunctionalize {

Decision::Decision(ProgramOp top, const Labels &solve)
    : program(top), labels(solve), ctx(top.getContext()) {}

Slot Decision::keyWith(Type carrier, const FlowPoint &point) const {
  if (!carriesLabels(carrier))
    return std::nullopt;
  return Key{unrestricted(carrier), labels.labelsOf(point)};
}

// What every value of a kind holds at `anchor`. A capture has no slot of
// its own: a closure's parts are its label's parameters.
Slot Decision::anchorKey(const FlowAnchor &anchor) const {
  std::optional<Type> carrier = anchor.slot();
  if (!carrier || !carriesLabels(*carrier))
    return std::nullopt;
  return Key{unrestricted(*carrier), labels.labelsOf(anchor)};
}

Slot Decision::keyOf(Value value) const {
  if (auto it = widened.find(value); it != widened.end())
    return it->second;
  return keyWith(value.getType(), FlowPoint::of(value));
}

Slot Decision::sinkOf(OpOperand &use) const {
  std::optional<FlowPoint> sink = labels.sinkOf(use);
  if (!sink)
    return std::nullopt;
  return idr::match(
      sink->at, [&](FlowPoint::Taken taken) { return keyOf(taken.use->get()); },
      [&](FlowPoint::Whole whole) { return keyOf(whole.value); },
      [&](const FlowPoint::Part &part) { return anchorKey(part.anchor); },
      [&](FlowPoint::Parameter param) {
        return signature(param.function.getAttr()).arguments[param.index];
      },
      [&](FlowPoint::Result result) {
        return signature(result.function.getAttr()).results[result.index];
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
    families.push_back(Family{*slot, DataType(), FlatSymbolRefAttr(), {}});
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
// source, which the op's flow interface declares.
void Decision::widen() {
  FlowEdges edges;
  program.walk([&](FlowOpInterface flow) {
    Operation *op = flow.getOperation();
    if (op->getNumResults() != 1 || !carriesLabels(op->getResult(0).getType()))
      return;
    Value value = op->getResult(0);
    edges.clear();
    flow.getFlowEdges(edges);
    bool made = llvm::any_of(edges.edges(), [&](const FlowEdges::Edge &edge) {
      return idr::match(
          edge.move, [&](const FlowEdges::Source &source) { return source.to == value; },
          [&](const FlowEdges::Constant &constant) { return constant.to == value; },
          [](const auto &) { return false; });
    });
    if (!made)
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
      widened[value] = *common;
  });
}

// Each function's calls, and in its row beside them each label it runs,
// with how many of its runs run it. A run has no tail kind until the
// rewrite makes it a call, and the atoms' join reads none, so it stands as
// a call within; the row stays in the graph's one order, a (callee, kind)
// once, merged with a direct call of the same label.
void Decision::complete(solver::ProgramGraph &graph,
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
  std::unique_ptr<Decision> decision(new Decision(program, labels));
  Decision &d = *decision;
  // Every signature first, which every other key of a parameter or a
  // result reads; then the widening, which reads the sinks; then every key
  // the program's values and types ask for, and the labels each run runs,
  // read in the same walk.
  for (FuncOp fn : program.getOps<FuncOp>()) {
    Signature &sig = d.signatures[fn.getSymNameAttr()];
    for (BlockArgument arg : fn.getArguments())
      sig.arguments.push_back(d.keyWith(arg.getType(), FlowPoint::of(Value(arg))));
    auto name = FlatSymbolRefAttr::get(fn.getSymNameAttr());
    for (auto [j, type] : llvm::enumerate(fn.getResultTypes()))
      sig.results.push_back(d.keyWith(type, FlowPoint::result(name, static_cast<unsigned>(j))));
  }
  d.widen();
  IndexVector<solver::FunctionId, footprint::Vector<solver::FunctionId>> ran(graph.size());
  for (FuncOp fn : program.getOps<FuncOp>()) {
    const Signature &sig = d.signature(fn.getSymNameAttr());
    FunctionType type = fn.getFunctionType();
    solver::FunctionId self = graph.id(fn);
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
  d.complete(graph, ran);
  IndexVector<solver::FunctionId, effects::Row> atoms =
      rows::solveAtoms(graph, ByGraph{}, *d.ctx, work);
  if (failed(d.declare(graph, atoms)))
    return failure();
  d.convertSignatures();
  // Each memo family's dispatch function, born rewritten.
  for (Family &family : d.families) {
    if (carrierOf(family.key) != Carrier::Lazy)
      continue;
    FailureOr<FuncOp> force = d.defineForce(family);
    if (failed(force))
      return failure();
    family.force = FlatSymbolRefAttr::get(force->getSymNameAttr());
    d.made.push_back(*force);
  }
  return decision;
}

} // namespace idr::defunctionalize
