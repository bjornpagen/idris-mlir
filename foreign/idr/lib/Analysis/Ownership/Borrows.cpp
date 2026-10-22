// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Borrow inference: which parameters, of functions and of join points, are
// views of their caller's value, counted nothing, and which are counted,
// under the frame-limited rule: a call holds a borrowed argument only where
// some active call still needs it after the call, or its type bounds all it
// reaches.
//
// A parameter is counted when the callee consumes any part of it (the
// parameter, or a field, a view of its buffer or an element read from it,
// moves whole into a cell, is released, taken apart, given back, forwarded
// into a region's result, or passed to a counted parameter), since what is
// read from a view is a view and no view is consumed; and when an op of
// upstream's reads any part of it, since such an op takes only the bare
// carrier and no op crosses a view into one. It is counted too when a call
// or jump gives it an argument it may not borrow: one bound at quantity 1,
// or one dead after the call that is neither static, nor a view (a scoped
// value, or a borrowed parameter of the caller or a part read from one),
// nor of a type that bounds all it reaches at a call that returns.
//
// A loan stands around the call, or around the join op a jump enters, and
// only where one may: nothing follows a tail call, and frames split a
// function at each call on its own cycle that returns to it, a frame per
// level, which no loan's region can be. So such a call, and a jump into a
// join point whose op holds one at any depth, lend nothing, as a tail call
// does: a parameter's grade is one for every caller, so a counted argument
// there makes the parameter counted, and the value is passed owned.
//
// One backward marking of the program's parameters, from those a body
// forces counted, along "counted here makes counted there": from a callee's
// to the caller's passed to it, from a caller's to the callee's it lends a
// view of. The root's parameters are counted (its caller is outside), a
// memo cell's are views (a force writes it while its caller reads it). A
// body's values are numbered by the solver's walk, whose one map lives
// while the body is read; what each is of a parameter is derived once, in
// that walk's order, into tables by number.
#include "idr/Analysis/Ownership.h"

#include "idr/Analysis/Ownership/Facts.h"
#include "idr/Analysis/Ownership/Walks.h"
#include "idr/Analysis/Solver/Extraction.h"
#include "idr/Analysis/Solver/Graph.h"
#include "idr/Analysis/Solver/Mark.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Ownership.h"
#include "idr/Support/Match.h"

#include "llvm/ADT/STLExtras.h"

#include <optional>
#include <tuple>
#include <utility>

using namespace mlir;

namespace idr {

namespace {

using solver::FunctionId;

struct ParameterNodes;
struct ParameterTag {
  using Minter = ParameterNodes;
};
using ParameterNode = Id<ParameterTag>;
struct ParameterNodes {
  static ParameterNode at(std::uint32_t n) { return ParameterNode(n); }
  static Count<ParameterNode> count(std::uint32_t n) { return Count<ParameterNode>(n); }
};

// A value of the body being read, by its place in the solver's walk.
struct BodyValueTag {
  using Minter = solver::Numbering<BodyValueTag>;
};
using BodyValue = Id<BodyValueTag>;

// A parameter whose convention no program changes, or one the marking
// decides.
enum class Fixed : std::uint8_t { Open, Counted, Viewed };

// What a parameter is to the marking: a node, or fixed.
struct Convention {
  Fixed fixed;
  std::uint32_t node;
};

// How a value stands to a parameter of its function: the parameter itself,
// or a part read of it, a view wherever the parameter is one.
enum class Holding : std::uint8_t { Whole, Part };

struct Owner {
  Convention param;
  Holding holding;
};

// Where the caller may lend an argument: around the call, which returns to
// it; around the join op whose region a jump enters; or nowhere.
enum class Lend : std::uint8_t { AroundCall, AroundJoin, Nowhere };

// Whether `value` is used, other than by `call`, where `call` may run first.
bool usedAfter(Value value, Operation *call) {
  return llvm::any_of(value.getUses(), [&](OpOperand &use) {
    return use.getOwner() != call && ownership::runsAfter(use.getOwner(), call);
  });
}

class Inference {
public:
  explicit Inference(const solver::ProgramGraph &graph)
      : graph(graph), params(graph.table<footprint::Vector<Convention>>()),
        joins(graph.table<footprint::Vector<Convention>>()) {}

  // Numbers every open parameter, reads every body, marks.
  void run() {
    for (FunctionId fn : graph.functions())
      number(fn);
    edges.emplace(ParameterNodes::count(nodes));
    for (FunctionId fn : graph.functions())
      readBody(fn);
    Csr<ParameterTag> marking = std::move(*edges).finish();
    counted.emplace(mark<Forward>(marking, std::span<const ParameterNode>(seeds)));
  }

  bool viewed(const Convention &convention) const {
    return convention.fixed == Fixed::Viewed ||
           (convention.fixed == Fixed::Open &&
            !counted->test(ParameterNodes::at(convention.node)));
  }

  const solver::ProgramGraph &graph;
  IndexVector<FunctionId, footprint::Vector<Convention>> params;
  IndexVector<FunctionId, footprint::Vector<Convention>> joins;

private:
  Convention conventionOf(FuncOp fn, Type type) {
    std::optional<Hold> hold = holdOf(type);
    if (hold && hold->release() == Release::Scoped)
      return {Fixed::Viewed, 0};
    if (!ownership::counted(type))
      return {Fixed::Counted, 0};
    if (fn.isRoot())
      return {Fixed::Counted, 0};
    if (ownership::isMemo(ownership::familyOf(type)))
      return {Fixed::Viewed, 0};
    return {Fixed::Open, nodes++};
  }

  void number(FunctionId id) {
    FuncOp fn = graph.op(id);
    for (BlockArgument param : fn.getBody().front().getArguments())
      params[id].push_back(conventionOf(fn, param.getType()));
    borrows::forEachJoinParameter(fn, [&](BlockArgument arg, std::uint32_t) {
      joins[id].push_back(conventionOf(fn, arg.getType()));
    });
  }

  // Whether frames split the function at `call`: a call that returns to its
  // caller, of a function on the caller's own cycle.
  bool framed(CallOp call) const {
    return call.getTailKind() == TailKind::nontail &&
           graph.sccOf(graph.id(call.getCalleeAttr())) == graph.sccOf(*current);
  }

  // The body's values numbered, its join parameters found, what each region
  // entry binds again, where a jump may lend, and the parameter each value
  // is or is read from, all before any use is judged; then every use.
  void readBody(FunctionId id) {
    current = id;
    fn = graph.op(id);
    numbering.emplace(fn);
    Count<BodyValue> count = numbering->size();
    joinOf.emplace(count);
    owners.emplace(count);
    joinLend.assign(joins[*current].size(), Lend::AroundJoin);
    borrows::forEachJoinParameter(fn, [&](BlockArgument arg, std::uint32_t at) {
      (*joinOf)[numbering->at(arg)] = at;
    });
    IndexVector<BodyValue, std::optional<BodyValue>> rebinds(count);
    fn.walk([&](Operation *op) {
      forwardedValues(op, [&](OpOperand &operand, Value input) {
        auto arg = dyn_cast<BlockArgument>(input);
        if (arg && arg.getOwner()->getParentOp() == op && !rebinds[numbering->at(arg)])
          rebinds[numbering->at(arg)] = numbering->at(operand.get());
      });
      if (auto call = dyn_cast<CallOp>(op); call && framed(call))
        lendNothingAround(call);
    });
    solver::inWalkOrder(fn, [&](Value value) {
      BodyValue at = numbering->at(value);
      (*owners)[at] = derive(value, at, rebinds);
    });
    fn.walk([&](Operation *op) {
      if (auto call = dyn_cast<CallOp>(op))
        return readCall(call);
      readUses(op);
    });
  }

  // No loan may stand around a join op that holds `call` at any depth, so a
  // jump into any of its join points lends nothing. A join op whose join
  // points lend nothing already was climbed through, with all above it.
  void lendNothingAround(CallOp call) {
    for (Operation *at = call->getParentOp(); at != fn.getOperation(); at = at->getParentOp()) {
      bool climbed = false;
      for (Region &region : at->getRegions())
        for (Block &block : region)
          for (BlockArgument arg : block.getArguments())
            if (std::optional<std::uint32_t> join = (*joinOf)[numbering->at(arg)]) {
              climbed = climbed || joinLend[*join] == Lend::Nowhere;
              joinLend[*join] = Lend::Nowhere;
            }
      if (climbed)
        return;
    }
  }

  // The parameter, of the function or of a join point, `value` is or is read
  // from, from what the walk's order derived first: through the positions
  // that hand a value on as itself, the region entries that bind it again
  // and what each part was read from. None for a value that holds no
  // reference, an element loaded from an array (its read takes a reference
  // of its own) and a value the body makes.
  std::optional<Owner> derive(Value value, BodyValue at,
                              const IndexVector<BodyValue, std::optional<BodyValue>> &rebinds) const {
    if (!holdsReferences(value.getType()))
      return std::nullopt;
    if (auto arg = dyn_cast<BlockArgument>(value)) {
      if (arg.getOwner() == &fn.getBody().front())
        return Owner{params[*current][arg.getArgNumber()], Holding::Whole};
      if (std::optional<std::uint32_t> join = (*joinOf)[at])
        return Owner{joins[*current][*join], Holding::Whole};
      if (std::optional<BodyValue> from = rebinds[at])
        return (*owners)[*from];
      return std::nullopt;
    }
    if (std::optional<Value> same = ownership::sameValueSource(value))
      return (*owners)[numbering->at(*same)];
    if (ownership::readOutOfElements(value))
      return std::nullopt;
    Value whole = ownership::readFrom(value);
    if (!whole)
      return std::nullopt;
    std::optional<Owner> owner = (*owners)[numbering->at(whole)];
    if (owner)
      owner->holding = Holding::Part;
    return owner;
  }

  // The parameter a counted `value` is or is read from; none for any other.
  std::optional<Owner> ownerOf(Value value) const {
    if (!ownership::counted(value.getType()))
      return std::nullopt;
    return (*owners)[numbering->at(value)];
  }

  void force(const Convention &convention) {
    if (convention.fixed == Fixed::Open)
      seeds.push_back(ParameterNodes::at(convention.node));
  }

  // Counted at `from` makes counted at `to`.
  void follows(const Convention &from, const Convention &to) {
    if (to.fixed != Fixed::Open)
      return;
    if (from.fixed == Fixed::Counted)
      force(to);
    else if (from.fixed == Fixed::Open)
      edges->edge(ParameterNodes::at(from.node), ParameterNodes::at(to.node));
  }

  // What the op does with each value it uses that is a parameter or is
  // read from one: consumes it (it moves whole into a cell, is released, is
  // taken apart, is given back, or is forwarded into a region's result), or
  // reads it as an op of upstream's, which counts the parameter; or hands it
  // to a join point, which is a call of it, as is every value a jump passes.
  void readUses(Operation *op) {
    // A position that hands a value on as itself is that value.
    if (op->hasTrait<SameValue>())
      return;
    if (ownership::carriersOnly(op)) {
      for (Value operand : op->getOperands())
        if (std::optional<Owner> owner = ownerOf(operand))
          force(owner->param);
      return;
    }
    forwardedValues(op, [&](OpOperand &operand, Value input) {
      if (auto arg = dyn_cast<BlockArgument>(input)) {
        if (std::optional<std::uint32_t> join = (*joinOf)[numbering->at(arg)])
          return readArgument(operand, joins[*current][*join], arg.getOwner()->getParentOp(),
                              joinLend[*join]);
        // The entry of a region binds the value again: it is that value.
        if (arg.getOwner()->getParentOp() == op)
          return;
      }
      if (std::optional<Owner> owner = ownerOf(operand.get()))
        force(owner->param);
    });
    // The op's own moves, as it declares them.
    auto declared = dyn_cast<FlowOpInterface>(op);
    if (!declared)
      return;
    FlowEdges flows;
    declared.getFlowEdges(flows);
    for (const FlowEdges::Edge &edge : flows.edges()) {
      if (!edge.carries(Carrier::Reference))
        continue;
      using Taken = std::optional<OpOperand *>;
      Taken taken = match(
          edge.move, [](const FlowEdges::Flow &flow) -> Taken { return flow.from.taken(); },
          [](const FlowEdges::Release &release) -> Taken { return release.use; },
          [](const auto &) -> Taken { return std::nullopt; });
      if (taken)
        if (std::optional<Owner> owner = ownerOf((*taken)->get()))
          force(owner->param);
    }
  }

  void readCall(CallOp call) {
    FunctionId callee = graph.id(call.getCalleeAttr());
    Lend lend = call.getTailKind() == TailKind::nontail && !framed(call) ? Lend::AroundCall
                                                                         : Lend::Nowhere;
    for (auto [index, operand] : llvm::enumerate(call->getOpOperands()))
      readArgument(operand, params[callee][index], call, lend);
  }

  // `operand`, passed to the parameter `to` at `site` (a call, or the join
  // op a jump enters), where `lend` says a loan of it may stand.
  void readArgument(OpOperand &operand, const Convention &to, Operation *site, Lend lend) {
    Value arg = operand.get();
    std::optional<Owner> owner = ownerOf(arg);
    // Counted here makes counted the caller's parameter the argument is or
    // is read from: a counted parameter consumes what it is passed, and no
    // view, nor anything read from one, is consumed.
    if (owner)
      follows(to, owner->param);
    if (to.fixed != Fixed::Open)
      return;
    // A value bound at quantity 1 moves to its one use: the callee counts.
    if (usesOf(arg.getType()) == Uses::Once)
      return force(to);
    std::optional<Hold> hold = holdOf(arg.getType());
    bool lent = hold && hold->release() != Release::Counted;
    // What the caller still needs after the site it lends around the site,
    // where a loan may stand: after a jump the join point's region runs and
    // the join op's results follow it.
    if (lent || (lend != Lend::Nowhere && usedAfter(arg, site)))
      return;
    // The caller's parameter lent on whole: a view while it is itself
    // borrowed.
    if (owner && owner->holding == Holding::Whole)
      return follows(owner->param, to);
    if (lend == Lend::AroundCall && ownership::boundsWhatItReaches(arg.getType()))
      return;
    // A part of the caller's parameter: a view while the parameter is one;
    // any other value is the callee's to count.
    if (owner)
      return follows(owner->param, to);
    force(to);
  }

  std::uint32_t nodes = 0;
  std::optional<CsrBuilder<ParameterTag>> edges;
  footprint::Vector<ParameterNode> seeds;
  std::optional<BitSet<ParameterNode>> counted;
  // The body being read and its tables by number, which go with it: each
  // value's join parameter and owner, and each join parameter's loan.
  std::optional<FunctionId> current;
  FuncOp fn;
  std::optional<solver::Numbering<BodyValueTag>> numbering;
  std::optional<IndexVector<BodyValue, std::optional<std::uint32_t>>> joinOf;
  std::optional<IndexVector<BodyValue, std::optional<Owner>>> owners;
  footprint::Vector<Lend> joinLend;
};

} // namespace

Borrows::Borrows(Operation *, AnalysisManager &am)
    : released(std::get<0>(reads(am)).table<footprint::Vector<Release>>()),
      joinReleased(std::get<0>(reads(am)).table<footprint::Vector<Release>>()) {
  const solver::ProgramGraph &graph = std::get<0>(reads(am));
  Inference inference(graph);
  inference.run();
  auto record = [&](footprint::Vector<Release> &into, Release release) {
    into.push_back(release);
    if (release == Release::Scoped)
      ++numViews;
  };
  for (FunctionId fn : graph.functions()) {
    for (auto [index, convention] : llvm::enumerate(inference.params[fn]))
      record(released[fn],
             inference.viewed(convention) && holdsReferences(graph.op(fn).getArgumentTypes()[index])
                 ? Release::Scoped
                 : Release::Counted);
    for (const Convention &convention : inference.joins[fn])
      record(joinReleased[fn], inference.viewed(convention) ? Release::Scoped : Release::Counted);
  }
}

} // namespace idr
