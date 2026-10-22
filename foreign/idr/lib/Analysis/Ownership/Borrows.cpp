// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Borrow inference: which parameters, of functions and of join points, are
// views of their caller's value, counted nothing, and which are counted,
// under the frame-limited rule: a call holds a borrowed argument only where
// some active call still needs it after the call, or its type bounds all it
// reaches.
//
// A parameter is counted when the callee consumes any part of it: the
// parameter, or a value read from it (a field, a view of its buffer, an
// element it holds), moves whole into a cell, is released, is taken apart
// (a rebuild site among those), is given back or forwarded into a region's
// result, or is passed to a counted parameter. What is read from a view is
// a view, and no view is consumed, so a part consumed makes the whole
// counted. A parameter is counted too when some call or jump gives it an
// argument it may not borrow: one bound at quantity 1 in the caller, or one
// dead after the call that is neither static, nor a view (a scoped value,
// or the caller's own parameter or a part read from one while that
// parameter is itself borrowed), nor of a type that bounds all it reaches
// at a call that is not a tail transfer. Every other parameter that holds a
// counted reference is a view.
//
// One backward marking of the program's parameters, from the parameters a
// body forces counted, along "counted here makes counted there": a callee's
// counted parameter to the caller's parameter passed to it, and a caller's
// counted parameter to the callee's parameter it lends a view of. A
// parameter rises once and walks its row once. The root's parameters are
// counted (its caller is outside) and a memo cell's are views (a force
// writes it while its caller reads it): fixed, they have no node.
#include "idr/Analysis/Ownership.h"

#include "idr/Analysis/Ownership/Facts.h"
#include "idr/Analysis/Ownership/Walks.h"
#include "idr/Analysis/Solver/Graph.h"
#include "idr/Analysis/Solver/Mark.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Ownership.h"
#include "idr/Support/Match.h"

#include "mlir/Interfaces/ControlFlowInterfaces.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"

#include <utility>

using namespace mlir;

namespace idr::borrows {

bool isJoinParameter(BlockArgument arg) {
  Region *region = arg.getOwner()->getParent();
  auto branch = dyn_cast_or_null<RegionBranchOpInterface>(region->getParentOp());
  if (!branch || arg.getOwner() != &region->front())
    return false;
  SmallVector<RegionSuccessor> entries;
  branch.getSuccessorRegions(RegionBranchPoint::parent(), entries);
  return llvm::none_of(entries, [&](RegionSuccessor &entry) { return entry.getSuccessor() == region; });
}

} // namespace idr::borrows

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

// A parameter whose convention no program changes, or one the marking
// decides.
enum class Fixed : std::uint8_t { Open, Counted, Viewed };

// What a parameter is to the marking: a node, or fixed.
struct Convention {
  Fixed fixed;
  std::uint32_t node;
};

// How a value stands to a parameter of its function: the parameter
// itself, or a part read of it (ownership::readFrom), a view wherever the
// parameter is one.
enum class Holding : std::uint8_t { Whole, Part };

struct Owner {
  Convention param;
  Holding holding;
};

// Whether `value` is used, other than by `call`, where the call may run
// before it.
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

  // The parameter, of the function or of one of its join points, that
  // `value` is or is read from: seen through the positions that hand a
  // value on as itself, the region entries that bind it again (a case's
  // refined scrutinee) and what each part was read from. None for a value
  // that holds no counted reference, which no part of a view is consumed
  // as, for an element loaded from an array, which holds its own reference
  // from its read, and for a value the body makes.
  std::optional<Owner> ownerOf(Value value) const {
    if (!ownership::counted(value.getType()))
      return std::nullopt;
    Holding holding = Holding::Whole;
    for (Value at = value;;) {
      if (auto arg = dyn_cast<BlockArgument>(at)) {
        if (arg.getOwner() == &fn.getBody().front())
          return Owner{params[*current][arg.getArgNumber()], holding};
        if (auto join = joinIndex.find(arg); join != joinIndex.end())
          return Owner{joins[*current][join->second], holding};
        auto entry = enteredFrom.find(arg);
        if (entry == enteredFrom.end())
          return std::nullopt;
        at = entry->second;
        continue;
      }
      if (std::optional<Value> same = ownership::sameValueSource(at)) {
        at = *same;
        continue;
      }
      if (ownership::readOutOfElements(at))
        return std::nullopt;
      if (Value whole = ownership::readFrom(at)) {
        at = whole;
        holding = Holding::Part;
        continue;
      }
      return std::nullopt;
    }
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

  void readBody(FunctionId id) {
    current = id;
    fn = graph.op(id);
    joinIndex.clear();
    enteredFrom.clear();
    borrows::forEachJoinParameter(fn, [&](BlockArgument arg, std::uint32_t at) {
      joinIndex.try_emplace(arg, at);
    });
    // What each region entry binds again, read before any use is judged.
    fn.walk([&](Operation *op) {
      forwardedValues(op, [&](OpOperand &operand, Value input) {
        auto arg = dyn_cast<BlockArgument>(input);
        if (arg && arg.getOwner()->getParentOp() == op && !joinIndex.contains(arg))
          enteredFrom.try_emplace(arg, operand.get());
      });
    });
    fn.walk([&](Operation *op) {
      if (auto call = dyn_cast<CallOp>(op))
        return readCall(call);
      readUses(op);
    });
  }

  // What the op does with each value it uses that is a parameter or is
  // read from one: consumes it (it moves whole into a cell, is released, is
  // taken apart, is given back, or is forwarded into a region's result),
  // which counts the parameter; or hands it to a join point, which is a
  // call of it, as is every value a jump passes.
  void readUses(Operation *op) {
    // A position that hands a value on as itself is that value.
    if (op->hasTrait<SameValue>())
      return;
    forwardedValues(op, [&](OpOperand &operand, Value input) {
      auto arg = dyn_cast<BlockArgument>(input);
      if (arg && joinIndex.contains(arg))
        return readArgument(operand, joins[*current][joinIndex.lookup(arg)], op, Transfer::Jump);
      // The entry of a region binds the value again: it is that value.
      if (arg && arg.getOwner()->getParentOp() == op)
        return;
      if (std::optional<Owner> owner = ownerOf(operand.get()))
        force(owner->param);
    });
    // The op's own moves, as it declares them; what it forwards was read
    // above.
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
          [](const FlowEdges::Unify &) -> Taken { return std::nullopt; },
          [](const FlowEdges::Source &) -> Taken { return std::nullopt; },
          [](const FlowEdges::Fresh &) -> Taken { return std::nullopt; },
          [](const FlowEdges::Overwrite &) -> Taken { return std::nullopt; },
          [](const FlowEdges::Constant &) -> Taken { return std::nullopt; },
          [](const FlowEdges::Dispatch &) -> Taken { return std::nullopt; });
      if (taken)
        if (std::optional<Owner> owner = ownerOf((*taken)->get()))
          force(owner->param);
    }
  }

  // How control reaches the callee: a call that may return to the caller,
  // a tail call (or one modulo context, whose context cells the caller has
  // built before it), or a jump to a join point, a tail transfer by
  // construction.
  enum class Transfer : std::uint8_t { Returns, Tail, Jump };

  void readCall(CallOp call) {
    FunctionId callee = graph.id(call.getCalleeAttr());
    Transfer transfer =
        call.getTailKind() == TailKind::nontail ? Transfer::Returns : Transfer::Tail;
    for (auto [index, operand] : llvm::enumerate(call->getOpOperands()))
      readArgument(operand, params[callee][index], call, transfer);
  }

  // `operand`, passed to the parameter `to` by `transfer`, at `site`.
  void readArgument(OpOperand &operand, const Convention &to, Operation *site,
                    Transfer transfer) {
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
    // After a jump, the join point's region runs and the join op's results
    // follow it: what is used after the join op is used after the jump.
    Operation *after = transfer == Transfer::Jump ? joinOpOf(operand) : site;
    if (lent || usedAfter(arg, after))
      return;
    // The caller's parameter lent on whole: a view while it is itself
    // borrowed.
    if (owner && owner->holding == Holding::Whole)
      return follows(owner->param, to);
    if (transfer == Transfer::Returns && ownership::boundsWhatItReaches(arg.getType()))
      return;
    // A part of the caller's parameter: a view while the parameter is one;
    // any other value dead after the call is the callee's to count.
    if (owner)
      return follows(owner->param, to);
    force(to);
  }

  // The join op whose region the jump's `operand` enters, read off the
  // input it becomes.
  Operation *joinOpOf(OpOperand &operand) {
    Operation *owner = operand.getOwner();
    Operation *join = owner;
    forwardedValues(owner, [&](OpOperand &forwarded, Value input) {
      if (&forwarded == &operand)
        if (auto arg = dyn_cast<BlockArgument>(input))
          join = arg.getOwner()->getParentOp();
    });
    return join;
  }

  std::uint32_t nodes = 0;
  std::optional<CsrBuilder<ParameterTag>> edges;
  footprint::Vector<ParameterNode> seeds;
  std::optional<BitSet<ParameterNode>> counted;
  // The body being read, and its one-body maps, the numbering's, which go
  // with it.
  std::optional<FunctionId> current;
  FuncOp fn;
  llvm::DenseMap<BlockArgument, std::uint32_t> joinIndex;
  llvm::DenseMap<BlockArgument, Value> enteredFrom;
};

} // namespace

Borrows::Borrows(Operation *, AnalysisManager &am)
    : released(am.getAnalysis<solver::ProgramGraph>().table<footprint::Vector<Release>>()),
      joinReleased(am.getAnalysis<solver::ProgramGraph>().table<footprint::Vector<Release>>()) {
  const solver::ProgramGraph &graph = am.getAnalysis<solver::ProgramGraph>();
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
