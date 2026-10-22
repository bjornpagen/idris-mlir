// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The local rule solved over the program (Unique.h). Each component of the
// program graph runs on the one static schedule, callees first, as rows
// are: its members' bodies are read, each member's results start at
// everything they may claim, and the members' bodies are solved again
// until no result falls. A body's solve starts every value it may raise at
// everything and lowers each to what its terms allow, a value whose source
// fell solved again: the greatest fixpoint, so a loop or a recursion keeps
// a value unique only where every way into it does. A path that ends the
// run forwards nothing and returns nothing, so it gives nothing. Each claim
// only falls, and each value falls at most twice, so the solve ends, with
// no count; its work is the values it evaluated.
//
// A component's task reads the IR and writes its own members' slots alone,
// reading only finished components' results and its own: no type is made
// and no lock is taken, and what each slot holds is what a serial run
// writes.
#include "idr/Transforms/InPlace/Unique.h"

#include "idr/Analysis/Ownership/Facts.h"
#include "idr/Analysis/Ownership/Walks.h"
#include "idr/Analysis/Solver/Schedule.h"
#include "idr/IR/Flow.h"

#include "mlir/Interfaces/InferTypeOpInterface.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"

#include <algorithm>
#include <utility>

using namespace mlir;

namespace idr::unique {

bool raisable(Type type) {
  std::optional<Hold> hold = holdOf(type);
  DataType data = ownership::familyOf(type);
  return hold && hold->release() != Release::Static && !hold->claims(Unique::Deep) && data &&
         !ownership::isMemo(data);
}

namespace {

using ownership::Term;
using ownership::Via;

// Whether `value` is one `op` makes: a result, or an argument of a block of
// one of its regions.
bool madeBy(Value value, Operation *op) {
  if (auto result = dyn_cast<OpResult>(value))
    return result.getOwner() == op;
  return cast<BlockArgument>(value).getOwner()->getParentOp() == op;
}

// Whether the op that makes a value declares it new.
enum class Made : std::uint8_t { Elsewhere, New };
enum class Inferred : std::uint8_t { No, Yes };

// Whether every term is a part read or taken out, and there is one: what
// an op that infers its results from the read table gives.
bool readOut(llvm::ArrayRef<Term<Local>> terms) {
  return !terms.empty() &&
         llvm::all_of(terms, [](const Term<Local> &term) { return term.via == Via::ReadOut; });
}

// The reading of one body. Its map from a value to its number is the
// numbering's: it lives while the body is read and goes with it.
class Reader {
public:
  Reader(FuncOp fn, const solver::ProgramGraph &graph) : graph(graph) { body.fn = fn; }

  Body read() {
    FuncOp fn = body.fn;
    ownership::forEachValue(fn, [&](Value value) {
      number.try_emplace(value, static_cast<Local>(body.values.size()));
      body.values.push_back(value);
    });
    std::size_t count = body.values.size();
    roles.assign(count, Role::Typed);
    made.assign(count, Made::Elsewhere);
    inferred.assign(count, Inferred::No);
    owners.assign(count, noLocal);
    fn.walk([&](Operation *op) { readOp(op); });
    readForwards();
    lay(count);
    if (auto ret = dyn_cast<ReturnOp>(fn.getBody().front().getTerminator())) {
      body.returns = Returns::Yes;
      for (Value operand : ret.getOperands())
        body.returned.push_back(number.lookup(operand));
    }
    return std::move(body);
  }

private:
  void readOp(Operation *op) {
    forwardedValues(op, [&](OpOperand &operand, Value input) {
      forwards.emplace_back(&operand, number.lookup(input));
    });
    if (auto call = dyn_cast<CallOp>(op)) {
      FunctionId callee = graph.id(call.getCalleeAttr());
      for (OpResult result : call->getResults()) {
        Local at = number.lookup(result);
        roles[at] = Role::Called;
        owners[at] = static_cast<Local>(body.calls.size());
        body.calls.push_back({callee, result.getResultNumber()});
      }
      return;
    }
    if (op->hasTrait<SameValue>()) {
      for (Value result : op->getResults()) {
        Local at = number.lookup(result);
        roles[at] = Role::Same;
        owners[at] = number.lookup(op->getOperand(0));
      }
      return;
    }
    // Its results are its inference's, which the write runs again; what it
    // reads of each operand is the claim it infers from.
    bool infers = isa<InferTypeOpInterface>(op);
    if (infers)
      for (Value operand : op->getOperands())
        body.inferring.push_back(number.lookup(operand));
    auto declared = dyn_cast<FlowOpInterface>(op);
    if (!declared)
      return;
    if (infers)
      for (Value result : op->getResults())
        inferred[number.lookup(result)] = Inferred::Yes;
    FlowEdges edges;
    declared.getFlowEdges(edges);
    ownership::forEachTerm(
        edges,
        [&](Value target, const Term<Value> &term) {
          if (!madeBy(target, op))
            return;
          Local from = term.from ? number.lookup(term.from) : noLocal;
          pending.emplace_back(number.lookup(target),
                               Term<Local>{from, term.via, term.reach, term.uses, term.held});
        },
        [&](Value target) {
          if (!madeBy(target, op))
            return;
          Local at = number.lookup(target);
          made[at] = Made::New;
          if (!infers && raisable(target.getType()) && ownership::flowsLinearly(target))
            roles[at] = Role::Raised;
        });
  }

  // Each input takes what each operand forwarded into it holds, and is
  // raised where it may be. An operand that becomes an input of several
  // successors (a match's scrutinee, one per case) is one value on each
  // path, since control goes to one successor of a branch point.
  void readForwards() {
    for (auto [operand, input] : forwards)
      pending.emplace_back(
          input, Term<Local>{number.lookup(operand->get()), Via::Moved, FieldReach::Other});
    for (auto [operand, input] : forwards) {
      Value value = body.values[input];
      if (roles[input] == Role::Typed && raisable(value.getType()) &&
          ownership::flowsLinearly(value))
        roles[input] = Role::Raised;
    }
  }

  // Each value's terms, contiguous by value, and who reads each value.
  void lay(std::size_t count) {
    std::stable_sort(pending.begin(), pending.end(),
                     [](const auto &a, const auto &b) { return a.first < b.first; });
    std::size_t next = 0;
    for (Local at = 0; at != count; ++at) {
      auto first = static_cast<std::uint32_t>(body.terms.size());
      for (; next != pending.size() && pending[next].first == at; ++next)
        body.terms.push_back(pending[next].second);
      auto last = static_cast<std::uint32_t>(body.terms.size());
      llvm::ArrayRef<Term<Local>> terms(body.terms.data() + first, last - first);
      Role role = roles[at];
      if (role == Role::Typed && inferred[at] == Inferred::Yes && readOut(terms))
        role = Role::Read;
      std::uint32_t owner = role == Role::Same || role == Role::Called ? owners[at] : first;
      body.nodes.push_back({role, ownership::claimOfSource(body.values[at]),
                            ownership::originOf<Local>(made[at] == Made::New, terms), owner,
                            last});
    }
    // Who reads each value: the values whose terms name it, and a Same
    // value of its operand.
    auto sources = [&](Local at, auto &&each) {
      const Node &node = body.nodes[at];
      if (node.role == Role::Same)
        return each(node.first);
      if (node.role != Role::Raised && node.role != Role::Read)
        return;
      for (std::uint32_t term = node.first; term != node.last; ++term)
        if (body.terms[term].from != noLocal)
          each(body.terms[term].from);
    };
    footprint::Vector<std::uint32_t> counts(count + 1, 0);
    for (Local at = 0; at != count; ++at)
      sources(at, [&](Local from) { ++counts[from + 1]; });
    for (std::size_t at = 1; at <= count; ++at)
      counts[at] += counts[at - 1];
    body.readerStart = counts;
    body.readers.assign(counts[count], noLocal);
    for (Local at = 0; at != count; ++at)
      sources(at, [&](Local from) { body.readers[counts[from]++] = at; });
  }

  const solver::ProgramGraph &graph;
  Body body;
  llvm::DenseMap<Value, Local> number;
  footprint::Vector<Role> roles;
  footprint::Vector<Made> made;
  footprint::Vector<Inferred> inferred;
  // A Same value's operand, a Called value's call.
  footprint::Vector<Local> owners;
  footprint::Vector<std::pair<OpOperand *, Local>> forwards;
  footprint::Vector<std::pair<Local, Term<Local>>> pending;
};

// Whether a value waits in a solve's worklist.
enum class Queued : std::uint8_t { No, Yes };

// What `at` is given now: its operand's claim, or what its terms allow,
// never less than its type says.
Unique evaluate(const Body &body, Local at) {
  const Node &node = body.nodes[at];
  if (node.role == Role::Same)
    return body.claims[node.first];
  llvm::ArrayRef<Term<Local>> terms(body.terms.data() + node.first, node.last - node.first);
  std::optional<Unique> proved = ownership::claimFrom<Local>(
      node.origin, terms, [&](Local from) { return body.claims[from]; });
  return ownership::greater(node.typed, proved.value_or(Unique::None));
}

// `body` solved given every callee's results: its claims, and the values it
// evaluated.
std::uint64_t solveBody(Body &body, const Results &results) {
  auto count = static_cast<Local>(body.nodes.size());
  body.claims.assign(count, Unique::Deep);
  footprint::Vector<Local> work;
  footprint::Vector<Queued> queued(count, Queued::No);
  for (Local at = count; at-- > 0;) {
    const Node &node = body.nodes[at];
    if (node.role == Role::Typed)
      body.claims[at] = node.typed;
    else if (node.role == Role::Called)
      body.claims[at] = results[body.calls[node.first].callee][body.calls[node.first].index];
    else {
      work.push_back(at);
      queued[at] = Queued::Yes;
    }
  }
  std::uint64_t steps = 0;
  while (!work.empty()) {
    Local at = work.back();
    work.pop_back();
    queued[at] = Queued::No;
    ++steps;
    Unique now = evaluate(body, at);
    if (now == body.claims[at])
      continue;
    body.claims[at] = now;
    for (std::uint32_t reader = body.readerStart[at]; reader != body.readerStart[at + 1];
         ++reader) {
      Local next = body.readers[reader];
      if (queued[next] == Queued::No) {
        queued[next] = Queued::Yes;
        work.push_back(next);
      }
    }
  }
  return steps;
}

} // namespace

Solution solve(const solver::ProgramGraph &graph, MLIRContext &context, solver::Work &work) {
  Solution out{graph.table<std::optional<Body>>(), graph.table<footprint::Vector<Unique>>()};
  solver::inSchedule<CalleesFirst>(graph, context, [&](solver::SccId component) {
    IdRange<FunctionId> members = graph.members(component);
    for (FunctionId f : members) {
      FuncOp fn = graph.op(f);
      out.bodies[f].emplace(Reader(fn, graph).read());
      for (Type type : fn.getResultTypes())
        out.results[f].push_back(raisable(type) ? Unique::Deep : ownership::claimOf(type));
    }
    // A function alone that does not call itself reads no result of its own,
    // so one solve settles it.
    bool alone = members.size() == 1 && !graph.callsItself(members.front());
    std::uint64_t steps = 0;
    for (bool fell = true; fell;) {
      fell = false;
      for (FunctionId f : members) {
        Body &body = *out.bodies[f];
        steps += solveBody(body, out.results);
        if (body.returns == Returns::No)
          continue;
        for (auto [index, type] : llvm::enumerate(graph.op(f).getResultTypes())) {
          if (!raisable(type))
            continue;
          Unique given =
              ownership::greater(ownership::claimOf(type), body.claims[body.returned[index]]);
          if (given != out.results[f][index]) {
            out.results[f][index] = given;
            fell = !alone;
          }
        }
      }
    }
    work.add(steps);
  });
  return out;
}

} // namespace idr::unique
