// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// An array a call gives back. The result is that array when every return is
// the argument the caller passed: the same value, or a borrow, a share, a
// linear enter, a linear use, or a constructor rebuilt from it, including
// that value read out of the record the call returns. A return that can be
// some other array is not.
//
// What each result is gets solved once for the module, in terms of the
// function's parameters, as a tree: a constructor every return built keeps
// what each of its fields is, so a field read out of the result on the
// caller's side is answered by the table, and nothing on that side walks
// the callee.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/Transforms/InBounds.h"

#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/UB/IR/UBOps.h"

#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/ScopeExit.h"
#include "llvm/ADT/SetVector.h"

#include <algorithm>

using namespace mlir;

namespace idr::inbounds {

namespace {

// Past this many projections, fields, hops or nested walks, the rest are
// no one argument.
constexpr unsigned originLimit = 64;

// A constructor of the fields just read from one value is that value: the
// array was taken apart and built back, and it is still that array.
std::optional<Value> rebuiltFrom(Value value) {
  auto con = value.getDefiningOp<ConOp>();
  if (!con || con.getFields().empty())
    return std::nullopt;
  StringAttr ctor = con.getCtor().getLeafReference();
  Value src;
  for (auto [i, field] : llvm::enumerate(con.getFields())) {
    std::optional<Component> part = componentOf(arrayRoot(field));
    if (!part || part->ctor != ctor || part->index != static_cast<uint64_t>(i))
      return std::nullopt;
    Value rec = arrayRoot(part->record);
    if (!src)
      src = rec;
    else if (src != rec)
      return std::nullopt;
  }
  return src;
}

// Views, a linear use, and a constructor rebuilt from the value under them.
// A linear position does not hide the value: entering it and using it are
// that array, as a borrow is.
Value peel(Value value) {
  for (unsigned n = 0; n < originLimit; ++n) {
    Value next = arrayRoot(value);
    if (auto use = next.getDefiningOp<LinUseOp>())
      next = use.getLinear();
    if (std::optional<Value> src = rebuiltFrom(next))
      next = *src;
    if (next == value)
      return value;
    value = next;
  }
  return value;
}

// One walk of the fixpoint: what a value of `fn` is, from the table as it
// stands. A result only ever meets down from unknown.
class Walk {
public:
  Walk(const Lengths::Local &whole, const DenseMap<Operation *, SmallVector<Origin>> &known)
      : whole(whole), known(known) {}

  Origin origin(FuncOp fn, Value value, ArrayRef<Proj> path) {
    if (depth++ > originLimit) {
      --depth;
      return Origin::none();
    }
    Origin found = walk(fn, value, path);
    --depth;
    return found;
  }

private:
  Origin walk(FuncOp fn, Value value, ArrayRef<Proj> path) {
    value = peel(value);
    // The program's poison, given where no run reads it, is any array.
    if (value.getDefiningOp<ub::PoisonOp>())
      return Origin::unknown();
    if (auto arg = dyn_cast<BlockArgument>(value))
      return argument(fn, arg, path);
    if (!visiting.insert(value).second)
      return Origin::none();
    llvm::scope_exit forget([&] { visiting.erase(value); });
    auto result = cast<OpResult>(value);
    if (auto call = dyn_cast<CallOp>(result.getOwner()))
      return callOrigin(fn, call, result.getResultNumber(), path);
    if (auto con = dyn_cast<ConOp>(result.getOwner())) {
      StringAttr ctor = con.getCtor().getLeafReference();
      if (path.empty()) {
        std::vector<Origin> fields;
        for (Value field : con.getFields())
          fields.push_back(origin(fn, field, {}));
        return Origin::built(ctor, std::move(fields));
      }
      Proj proj = path.front();
      if (ctor == proj.ctor && proj.index < con.getFields().size())
        return origin(fn, con.getFields()[proj.index], path.drop_front());
      return Origin::none();
    }
    // A field read out of a value is that field of it.
    if (std::optional<Component> part = componentOf(value)) {
      SmallVector<Proj, 4> longer{{part->ctor, part->index}};
      longer.append(path.begin(), path.end());
      return origin(fn, part->record, longer);
    }
    if (std::optional<Join> join = joinOf(value, whole); join && join->local)
      return meetIncoming(fn, join->incoming, path);
    return Origin::none();
  }

  Origin argument(FuncOp fn, BlockArgument arg, ArrayRef<Proj> path) {
    if (arg.getOwner() == &fn.getBody().front())
      return Origin::arg(arg.getArgNumber(), path);
    if (auto it = assumed.find(arg); it != assumed.end())
      return it->second;
    if (auto loop = dyn_cast<scf::WhileOp>(arg.getOwner()->getParentOp())) {
      unsigned index = arg.getArgNumber();
      if (arg.getOwner() == loop.getAfterBody())
        return origin(fn, loop.getConditionOp().getArgs()[index], path);
      return carried(fn, arg, loop.getInits()[index], loop.getYieldOp().getOperand(index), path);
    }
    if (auto loop = dyn_cast<scf::ForOp>(arg.getOwner()->getParentOp())) {
      unsigned index = arg.getArgNumber();
      if (index == 0)
        return Origin::none();
      return carried(fn, arg, loop.getInitArgs()[index - 1],
                     loop.getBody()->getTerminator()->getOperand(index - 1), path);
    }
    if (std::optional<Component> part = componentOf(arg)) {
      SmallVector<Proj, 4> longer{{part->ctor, part->index}};
      longer.append(path.begin(), path.end());
      return origin(fn, part->record, longer);
    }
    if (std::optional<Join> join = joinOf(arg, whole); join && join->local)
      return meetIncoming(fn, join->incoming, path);
    return Origin::none();
  }

  // A loop argument is the value it starts as when what the loop yields for
  // it is that value too, under the hypothesis that the argument is.
  Origin carried(FuncOp fn, BlockArgument arg, Value init, Value yielded, ArrayRef<Proj> path) {
    Origin initial = origin(fn, init, path);
    if (initial.kind != Origin::Argument && initial.kind != Origin::Built)
      return initial;
    assumed[arg] = initial;
    Origin back = origin(fn, yielded, path);
    assumed.erase(arg);
    return initial.meet(back);
  }

  // The table says what the whole result is, a projection of it included.
  // A result the table has not constrained is left so: a recursive call
  // still in the fixpoint, and walking it again is not a smaller question.
  Origin callOrigin(FuncOp fn, CallOp call, unsigned slot, ArrayRef<Proj> path) {
    auto callee = whole.symbols().lookup<FuncOp>(call.getCallee());
    auto it = callee ? known.find(callee) : known.end();
    if (!callee || it == known.end() || slot >= it->second.size())
      return Origin::none();
    Origin result = it->second[slot];
    for (Proj proj : path)
      result = result.project(proj);
    return inCaller(fn, call, result);
  }

  // `result`, of the callee's parameters, as what the caller passed them.
  Origin inCaller(FuncOp fn, CallOp call, const Origin &result) {
    switch (result.kind) {
    case Origin::Unknown:
    case Origin::None:
      return result;
    case Origin::Argument:
      if (result.argument >= call.getArgOperands().size())
        return Origin::none();
      return origin(fn, call.getArgOperands()[result.argument], result.inside);
    case Origin::Built:
      break;
    }
    if (depth++ > originLimit) {
      --depth;
      return Origin::none();
    }
    std::vector<Origin> fields;
    for (const Origin &field : result.fields)
      fields.push_back(inCaller(fn, call, field));
    --depth;
    return Origin::built(result.ctor, std::move(fields));
  }

  Origin meetIncoming(FuncOp fn, ArrayRef<Value> incoming, ArrayRef<Proj> path) {
    if (incoming.empty())
      return Origin::none();
    Origin acc = Origin::unknown();
    bool concrete = false;
    for (Value in : incoming) {
      // A place that gives the program's poison constrains nothing.
      if (peel(in).getDefiningOp<ub::PoisonOp>())
        continue;
      concrete = true;
      acc = acc.meet(origin(fn, in, path));
    }
    return concrete ? acc : Origin::unknown();
  }

  const Lengths::Local &whole;
  const DenseMap<Operation *, SmallVector<Origin>> &known;
  DenseMap<Value, Origin> assumed;
  DenseSet<Value> visiting;
  unsigned depth = 0;
};

} // namespace

DenseMap<Operation *, SmallVector<Origin>> returnedOrigins(ModuleOp module,
                                                          const Lengths::Local &whole) {
  DenseMap<Operation *, SmallVector<Origin>> known;
  SmallVector<FuncOp> functions;
  for (auto fn : module.getOps<FuncOp>()) {
    if (fn.isExternal() || fn.getNumResults() == 0)
      continue;
    functions.push_back(fn);
    known[fn].assign(fn.getNumResults(), Origin::unknown());
  }
  DenseMap<Operation *, SetVector<Operation *>> callers;
  for (FuncOp fn : functions)
    fn.walk([&](CallOp call) {
      if (auto callee = whole.symbols().lookup<FuncOp>(call.getCallee()))
        if (known.contains(callee))
          callers[callee].insert(fn);
    });
  // The order does not matter, and a function is walked again only when a
  // callee's result changed. Walking every function whenever any one
  // changed walks the module once per function on a chain of calls.
  SetVector<Operation *> work;
  for (FuncOp fn : llvm::reverse(functions))
    work.insert(fn);
  while (!work.empty()) {
    auto fn = cast<FuncOp>(work.pop_back_val());
    SmallVector<Origin> now(fn.getNumResults(), Origin::unknown());
    ArrayRef<ReturnOp> returns = whole.lengths().returnsOf(fn);
    for (ReturnOp ret : returns) {
      Walk walk(whole, known);
      for (auto [i, operand] : llvm::enumerate(ret.getOperands()))
        if (i < now.size())
          now[i] = now[i].meet(walk.origin(fn, operand, {}));
    }
    if (returns.empty())
      now.assign(now.size(), Origin::none());
    if (now == known[fn])
      continue;
    known[fn] = std::move(now);
    for (Operation *caller : callers.lookup(fn.getOperation()))
      work.insert(caller);
  }
  return known;
}

// None when `value` is not a call's value, or some return is another array.
std::optional<GivenBack> Lengths::Local::givenBack(Value value) {
  if (!chasing.insert(value).second)
    return std::nullopt;
  llvm::scope_exit forget([&] { chasing.erase(value); });
  SmallVector<Proj, 4> path;
  Value cur = arrayRoot(value);
  for (unsigned n = 0; n < originLimit; ++n) {
    if (auto call = cur.getDefiningOp<CallOp>()) {
      std::reverse(path.begin(), path.end());
      return fromCall(call, cast<OpResult>(cur).getResultNumber(), path);
    }
    std::optional<Component> part = componentOf(cur);
    if (!part)
      return std::nullopt;
    path.push_back({part->ctor, part->index});
    cur = arrayRoot(part->record);
  }
  return std::nullopt;
}

std::optional<GivenBack> Lengths::Local::fromCall(CallOp call, unsigned slot, ArrayRef<Proj> path) {
  auto callee = symbols().lookup<FuncOp>(call.getCallee());
  if (!callee)
    return std::nullopt;
  Origin given = lengths().given(callee, slot);
  for (Proj proj : path)
    given = given.project(proj);
  if (given.kind != Origin::Argument || given.argument >= call.getArgOperands().size())
    return std::nullopt;
  Value materialized = materialize(call.getArgOperands()[given.argument], given.inside);
  if (!materialized)
    return std::nullopt;
  return GivenBack{call, materialized};
}

// Read `path` from `value`. A call that gives the value back is that value,
// so the field is read from what the caller passed.
Value Lengths::Local::materialize(Value value, ArrayRef<Proj> path) {
  Value cur = value;
  for (Proj proj : path) {
    cur = arrayRoot(cur);
    for (unsigned hop = 0; hop < originLimit && !cur.getDefiningOp<ConOp>(); ++hop) {
      std::optional<GivenBack> nested = givenBack(cur);
      if (!nested || nested->value == cur)
        break;
      cur = arrayRoot(nested->value);
    }
    auto con = cur.getDefiningOp<ConOp>();
    if (!con || con.getCtor().getLeafReference() != proj.ctor || proj.index >= con.getFields().size())
      return {};
    cur = con.getFields()[proj.index];
  }
  return cur;
}

} // namespace idr::inbounds
