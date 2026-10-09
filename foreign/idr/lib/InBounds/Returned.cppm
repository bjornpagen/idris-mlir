// idr.inbounds:returned: an array a call gives back. The result is that
// array when every return is the argument the caller passed: the same
// value, or a borrow, a share, a linear enter, a linear use, or a
// constructor rebuilt from it, including that value read out of the record
// the call returns. A return that can be some other array is not. The
// arrays are judged on the module as it is, by whoever owns the Lengths
// that asks.
export module idr.inbounds:returned;

import idr.mlir;
import idr.dialect;

import :joins;

using namespace mlir;

namespace idr::inbounds {

// An array a call gives back, and the operand of that call it is. `call`
// is the call the returned value was read out of, so a size returned
// beside it from the same call can be read the same way.
export struct GivenBack {
  func::CallOp call;
  Value value;
};

constexpr unsigned originLimit = 64;

struct Proj {
  StringAttr ctor;
  uint64_t index;
};

// What a value in a callee is: not yet constrained, no one argument, or one
// argument, with the projections still to read from it.
struct Origin {
  enum Kind { Unknown, None, Argument } kind = Unknown;
  unsigned argument = 0;
  SmallVector<Proj, 4> inside;

  static Origin unknown() { return {}; }
  static Origin none() { return {None, 0, {}}; }
  static Origin arg(unsigned index, ArrayRef<Proj> path = {}) {
    return {Argument, index, SmallVector<Proj, 4>(path)};
  }

  bool operator==(const Origin &other) const {
    if (kind != other.kind)
      return false;
    if (kind != Argument)
      return true;
    if (argument != other.argument || inside.size() != other.inside.size())
      return false;
    for (auto [a, b] : llvm::zip(inside, other.inside))
      if (a.ctor != b.ctor || a.index != b.index)
        return false;
    return true;
  }

  Origin meet(Origin other) const {
    if (kind == Unknown)
      return other;
    if (other.kind == Unknown || *this == other)
      return *this;
    return none();
  }
};

namespace {

struct Forget {
  DenseSet<Value> *set = nullptr;
  Value value;
  Forget(DenseSet<Value> &set, Value value) : set(&set), value(value) {}
  Forget(const Forget &) = delete;
  Forget &operator=(const Forget &) = delete;
  ~Forget() {
    if (set)
      set->erase(value);
  }
};

struct ForgetOp {
  DenseSet<Operation *> *set = nullptr;
  Operation *op = nullptr;
  ForgetOp(DenseSet<Operation *> &set, Operation *op) : set(&set), op(op) {}
  ForgetOp(const ForgetOp &) = delete;
  ForgetOp &operator=(const ForgetOp &) = delete;
  ~ForgetOp() {
    if (set)
      set->erase(op);
  }
};

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

} // namespace

// What each function's results are, solved on construction. Whoever holds
// it keeps the module's functions, their calls and their returns as they
// are while it asks; `calls` is that owner's, of the same module.
class ReturnedArrays {
public:
  ReturnedArrays(ModuleOp module, const Calls &calls) : calls(calls), symbols(module) {
    for (auto fn : module.getOps<func::FuncOp>()) {
      if (fn.isExternal() || fn.empty() || fn.getNumResults() == 0)
        continue;
      functions.push_back(fn);
      known[fn].assign(fn.getNumResults(), Origin::unknown());
    }
    for (bool changed = true; changed;) {
      changed = false;
      for (func::FuncOp fn : functions) {
        SmallVector<Origin> now(fn.getNumResults(), Origin::unknown());
        bool saw = false;
        fn.walk([&](func::ReturnOp ret) {
          saw = true;
          for (auto [i, operand] : llvm::enumerate(ret.getOperands()))
            if (i < now.size())
              now[i] = now[i].meet(origin(fn, operand, {}));
        });
        if (!saw)
          now.assign(now.size(), Origin::none());
        if (now != known[fn]) {
          known[fn] = std::move(now);
          changed = true;
        }
      }
    }
  }

  // The caller-side value `value` is, when a call gives it back as an
  // argument. None when it is not a call's value, or some return is another
  // array.
  std::optional<GivenBack> given(Value value) {
    if (!chasing.insert(value).second)
      return std::nullopt;
    Forget forget(chasing, value);
    value = arrayRoot(value);
    SmallVector<Proj, 4> path;
    Value cur = value;
    for (unsigned n = 0; n < originLimit; ++n) {
      if (auto call = cur.getDefiningOp<func::CallOp>()) {
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

private:
  std::optional<GivenBack> fromCall(func::CallOp call, unsigned slot, ArrayRef<Proj> path) {
    auto callee = symbols.lookup<func::FuncOp>(call.getCalleeAttr().getAttr());
    if (!callee || !known.contains(callee) || slot >= callee.getNumResults())
      return std::nullopt;
    Origin acc = Origin::unknown();
    bool saw = false;
    callee.walk([&](func::ReturnOp ret) {
      if (slot >= ret.getNumOperands())
        return;
      saw = true;
      acc = acc.meet(origin(callee, ret.getOperand(slot), path));
    });
    if (!saw || acc.kind != Origin::Argument || acc.argument >= call.getNumOperands())
      return std::nullopt;
    Value materialized = materialize(call.getOperand(acc.argument), acc.inside);
    if (!materialized)
      return std::nullopt;
    return GivenBack{call, materialized};
  }

  // Read `path` from `value`. A call that gives the value back is that
  // value, so the field is read from what the caller passed.
  Value materialize(Value value, ArrayRef<Proj> path) {
    Value cur = value;
    for (Proj proj : path) {
      cur = arrayRoot(cur);
      for (unsigned hop = 0; hop < originLimit && !cur.getDefiningOp<ConOp>(); ++hop) {
        std::optional<GivenBack> nested = given(cur);
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

  Origin origin(func::FuncOp fn, Value value, ArrayRef<Proj> path) {
    if (depth++ > originLimit) {
      --depth;
      return Origin::none();
    }
    Origin found = walk(fn, value, path);
    --depth;
    return found;
  }

  Origin walk(func::FuncOp fn, Value value, ArrayRef<Proj> path) {
    value = peel(value);
    // The program's poison, given where no run reads it, is any array.
    if (value.getDefiningOp<ub::PoisonOp>())
      return Origin::unknown();
    if (auto arg = dyn_cast<BlockArgument>(value))
      return argument(fn, arg, path);
    if (!visiting.insert(value).second)
      return Origin::none();
    Forget forget(visiting, value);
    auto result = cast<OpResult>(value);
    if (auto call = dyn_cast<func::CallOp>(result.getOwner()))
      return callOrigin(fn, call, result.getResultNumber(), path);
    if (!path.empty()) {
      if (auto con = dyn_cast<ConOp>(result.getOwner())) {
        Proj proj = path.front();
        if (con.getCtor().getLeafReference() == proj.ctor && proj.index < con.getFields().size())
          return origin(fn, con.getFields()[proj.index], path.drop_front());
        return Origin::none();
      }
    }
    // A field read out of a value is that field of it.
    if (std::optional<Component> part = componentOf(value)) {
      SmallVector<Proj, 4> longer{{part->ctor, part->index}};
      longer.append(path.begin(), path.end());
      return origin(fn, part->record, longer);
    }
    if (std::optional<Join> join = joinOf(value, calls))
      return meetIncoming(fn, join->incoming, path);
    return Origin::none();
  }

  Origin argument(func::FuncOp fn, BlockArgument arg, ArrayRef<Proj> path) {
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
    if (std::optional<Join> join = joinOf(arg, calls))
      return meetIncoming(fn, join->incoming, path);
    return Origin::none();
  }

  // A loop argument is the value it starts as when what the loop yields for
  // it is that value too, under the hypothesis that the argument is.
  Origin carried(func::FuncOp fn, BlockArgument arg, Value init, Value yielded, ArrayRef<Proj> path) {
    Origin initial = origin(fn, init, path);
    if (initial.kind != Origin::Argument)
      return initial;
    assumed[arg] = initial;
    Origin back = origin(fn, yielded, path);
    assumed.erase(arg);
    return initial.meet(back);
  }

  // The table says what the whole result is. A projection of a result that
  // is not itself an argument is read from the callee with that projection.
  // A result the table has not constrained is left so: a recursive call
  // still in the fixpoint, and walking it again is not a smaller question.
  Origin callOrigin(func::FuncOp fn, func::CallOp call, unsigned slot, ArrayRef<Proj> path) {
    auto callee = symbols.lookup<func::FuncOp>(call.getCalleeAttr().getAttr());
    auto it = callee ? known.find(callee) : known.end();
    if (!callee || it == known.end() || slot >= it->second.size())
      return Origin::none();
    Origin knownResult = it->second[slot];
    if (knownResult.kind == Origin::Unknown)
      return knownResult;
    if (knownResult.kind == Origin::Argument) {
      SmallVector<Proj, 4> longer(knownResult.inside);
      longer.append(path.begin(), path.end());
      return origin(fn, call.getOperand(knownResult.argument), longer);
    }
    if (path.empty())
      return knownResult;
    if (!rewalking.insert(callee).second)
      return Origin::unknown();
    ForgetOp forget(rewalking, callee);
    Origin acc = Origin::unknown();
    bool saw = false;
    callee.walk([&](func::ReturnOp ret) {
      if (slot >= ret.getNumOperands())
        return;
      saw = true;
      acc = acc.meet(origin(callee, ret.getOperand(slot), path));
    });
    if (!saw || acc.kind != Origin::Argument)
      return saw ? acc : Origin::none();
    return origin(fn, call.getOperand(acc.argument), acc.inside);
  }

  Origin meetIncoming(func::FuncOp fn, ArrayRef<Value> incoming, ArrayRef<Proj> path) {
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

  const Calls &calls;
  SymbolTable symbols;
  SmallVector<func::FuncOp> functions;
  DenseMap<Operation *, SmallVector<Origin>> known;
  DenseMap<Value, Origin> assumed;
  DenseSet<Value> visiting;
  DenseSet<Value> chasing;
  DenseSet<Operation *> rewalking;
  unsigned depth = 0;
};

} // namespace idr::inbounds
