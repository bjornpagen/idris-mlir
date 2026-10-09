// idr.inbounds:lengths: which integers are the lengths of which arrays.
// `related(n, a)` holds when, wherever `n` and `a` are both in scope, the
// array `a` has `max(n, 0)` elements: what `idr.array.new [%n]` gives, and
// what the program then carries apart.
//
// A component of a record — a field read, a field a take yields, an
// argument of a match case — has the length of the component the
// constructor stored. Two values one constructor built stay related after
// the record is taken apart; an array stored alone stays related to the
// size it was built with. The constructor is what pairs them. A read of
// another constructor's field is not that component, and a record no
// constructor in scope built pairs nothing.
//
// A size measured off the array (its dimension made i64) is its length,
// however the array was made: a length never changes, and the views of an
// array share it.
//
// A size the array was made from relates when it is that operand, or the
// same integer clamped at 0, on either side. A branch (a match, an if) or a
// select or a max has that clamp when every side does, which for a side is
// either the values themselves or what the conditions choosing that side
// force. Those conditions are how the value was built, so the equality
// holds wherever the value is in scope, not only on the path that built
// it. A loop's own guard is not part of it: a fact that holds only while
// the loop runs is not a length everywhere the values are in scope.
//
// The relation of a pair is decided by where its values come from. An
// array made of a size relates to that size. A pair bound at one join (two
// arguments of one function, of one loop, two results of one region op or
// call) is related when every place binding them gives a related pair; a
// value bound at a join and one fixed around it (a size defined before the
// loop that carries the array) when every place gives a value related to
// the fixed one. A call that gives the array back — the same value, or a
// borrow, a share, a linear enter, a linear use or a constructor rebuilt
// from it, or that value read out of the record the call returns — is that
// array, so the pair is the one the caller passed. A size the same call
// gives back as an argument is that argument too. A return that can be
// some other array leaves the pair unrelated. Pairs reach each other in
// cycles (a loop gives back what it took), so the answer is the greatest
// fixpoint: every pair reached is
// taken to hold, and each that needs a pair that fails, or that comes from
// anything else, fails, until none changes. What remains holds by
// induction over the run: each binding of a pair that holds is made of
// pairs that held. A poison array is no array any access may read, so it
// relates to every size; a poison record likewise holds no component an
// access may read. A poison size relates to no array, since an access that
// never branches on it would read the array unchecked.
export module idr.inbounds:lengths;

import idr.mlir;
import idr.dialect;

import :components;
import :joins;
import :paths;
import :returned;
import :system;

using namespace mlir;
using namespace mlir::dataflow;

namespace idr::inbounds {

namespace {

// Past this many pairs reached from one question, the rest fail: an
// answer is then only weaker. Past this many values followed while
// walking one clamp, the rest fail the same way.
constexpr size_t pairLimit = 4096;
constexpr unsigned walkLimit = 64;
constexpr unsigned edgeLimit = 64;

int64_t clampedConst(const APInt &size) { return std::max<int64_t>(size.getSExtValue(), 0); }

// Erases `value` from `set` when destroyed, so a walk can visit it again
// on another branch.
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

} // namespace

export class Lengths {
public:
  explicit Lengths(ModuleOp module, DataFlowSolver &solver) : calls(module), solver(solver) {}

  // Whether the array `array` has `size` clamped at 0 elements wherever
  // both are in scope.
  bool related(Value size, Value array) {
    // A call that returns the array it was given is that array. Follow it
    // before the pair is asked, a bounded number of times: each step is an
    // operand of the call, and past the bound the pair stays unrelated.
    array = arrayRoot(array);
    for (unsigned hop = 0; hop < 64; ++hop) {
      std::optional<GivenBack> back = arrayGivenBack(array);
      if (!back || back->value == array)
        break;
      if (std::optional<GivenBack> sizeBack = arrayGivenBack(size);
          sizeBack && sizeBack->call == back->call)
        size = sizeBack->value;
      array = arrayRoot(back->value);
    }
    Pair start{size, array};
    if (auto it = index.find(start); it == index.end())
      solve(start);
    return nodes[index.lookup(start)].state == State::Held;
  }

private:
  using Pair = std::pair<Value, Value>;
  enum class State { Open, Held, Broken };
  struct Node {
    State state = State::Open;
    SmallVector<unsigned> needs;
    SmallVector<unsigned> neededBy;
  };

  // Whether `max(size, 0)` and `max(made, 0)` are the same integer, from
  // how `made` is built. A side that already is agrees without the
  // conditions; one that is not must be forced by the conditions that
  // choose it. A loop is not walked: its guard holds on its iterations,
  // and the length is claimed wherever both values are in scope.
  bool clampsEqual(Value size, Value made) {
    Pair key{size, made};
    if (auto it = clampCache.find(key); it != clampCache.end())
      return it->second;
    if (!clampOpen.insert(key).second)
      return false;
    DenseSet<Value> seen;
    bool equal = agrees(size, made, seen);
    clampOpen.erase(key);
    clampCache[key] = equal;
    return equal;
  }

  bool agrees(Value size, Value made, DenseSet<Value> &seen) {
    if (!size.getType().isInteger(64) || !made.getType().isInteger(64))
      return false;
    if (size == made)
      return true;
    APInt a, b;
    if (matchPattern(size, m_ConstantInt(&a)) && matchPattern(made, m_ConstantInt(&b)))
      return clampedConst(a) == clampedConst(b);
    // A size already clamped at 0 has the clamp of what it clamps: the
    // dimension of an array made here folds to its size clamped so.
    if (std::optional<Value> clamps = clampOf(size))
      return agrees(*clamps, made, seen);
    if (seen.size() >= walkLimit || !seen.insert(made).second)
      return false;
    Forget forget(seen, made);
    if (std::optional<Value> clamps = clampOf(made))
      return agrees(size, *clamps, seen);
    if (auto max = made.getDefiningOp<arith::MaxSIOp>())
      return agrees(size, max.getLhs(), seen) && agrees(size, max.getRhs(), seen);
    if (auto select = made.getDefiningOp<arith::SelectOp>();
        select && select.getCondition().getType().isInteger(1))
      return atPoint(select, select.getCondition(), true, size, select.getTrueValue(), seen) &&
             atPoint(select, select.getCondition(), false, size, select.getFalseValue(), seen);
    auto branch = dyn_cast_or_null<RegionBranchOpInterface>(made.getDefiningOp());
    if (branch && !branch.hasLoop())
      return eachEdge(branch, size, made, seen);
    return false;
  }

  // `made`, at `at`, agrees with `size`. `condition` chose this side when
  // it is set. A side that agrees on its own needs no condition.
  bool atPoint(Operation *at, Value condition, bool holds, Value size, Value made,
               DenseSet<Value> &seen) {
    if (agrees(size, made, seen))
      return true;
    System system(solver, knownAt(at, dominance));
    pathFacts(at, system);
    if (condition)
      system.assume(condition, holds);
    return system.sameClamp(size, made);
  }

  bool eachEdge(RegionBranchOpInterface branch, Value size, Value made, DenseSet<Value> &seen) {
    RegionSuccessor successor(branch.getOperation());
    std::optional<unsigned> position = positionIn(branch.getSuccessorInputs(successor), made);
    if (!position)
      return false;
    SmallVector<Value> values;
    branch.getPredecessorValues(successor, static_cast<int>(*position), values);
    SmallVector<RegionBranchPoint> points;
    branch.getPredecessors(successor, points);
    if (values.empty() || values.size() != points.size() || values.size() > edgeLimit)
      return false;
    for (auto [i, point] : llvm::enumerate(points)) {
      Operation *at = point.isParent() ? branch.getOperation() : point.getTerminatorPredecessorOrNull();
      if (!at || !atPoint(at, Value(), true, size, values[i], seen))
        return false;
    }
    return true;
  }

  // The pairs `pair` holds by, all needed; none when it cannot hold.
  std::optional<SmallVector<Pair>> needsOf(Pair pair) {
    auto [size, array] = pair;
    if (array.getDefiningOp<ub::PoisonOp>())
      return SmallVector<Pair>{};
    if (std::optional<Value> of = measured(size); of && arrayRoot(*of) == arrayRoot(array))
      return SmallVector<Pair>{};
    if (ComponentPairs parts = componentPairs(calls, dominance, size, array); parts.component)
      return parts.needs;
    std::optional<Join> sizeJoin = joinOf(size, calls);
    std::optional<Join> arrayJoin = joinOf(array, calls);
    SmallVector<Pair> needs;
    if (sizeJoin && arrayJoin && sizeJoin->key == arrayJoin->key) {
      for (auto [n, a] : llvm::zip_equal(sizeJoin->incoming, arrayJoin->incoming))
        needs.push_back({n, arrayRoot(a)});
      return needs;
    }
    if (arrayJoin && arrayJoin->local && dominance.properlyDominates(size, arrayJoin->owner)) {
      for (Value a : arrayJoin->incoming)
        needs.push_back({size, arrayRoot(a)});
      return needs;
    }
    if (sizeJoin && sizeJoin->local && dominance.properlyDominates(array, sizeJoin->owner)) {
      for (Value n : sizeJoin->incoming)
        needs.push_back({n, array});
      return needs;
    }
    Value made;
    // A guarded array has one dimension, so one size.
    if (auto fresh = array.getDefiningOp<ArrayNewOp>(); fresh && fresh.getSizes().size() == 1)
      made = fresh.getSizes().front();
    else if (auto generated = array.getDefiningOp<ArrayGenerateOp>())
      made = generated.getSize();
    if (!made)
      return std::nullopt;
    if (made == size)
      return needs;
    APInt a, b;
    if (matchPattern(size, m_ConstantInt(&a)) && matchPattern(made, m_ConstantInt(&b)) &&
        clampedConst(a) == clampedConst(b))
      return needs;
    if (clampsEqual(size, made))
      return needs;
    return std::nullopt;
  }

  unsigned nodeOf(Pair pair, SmallVectorImpl<unsigned> &fresh) {
    auto [it, inserted] = index.try_emplace(pair, nodes.size());
    if (inserted) {
      nodes.emplace_back();
      fresh.push_back(it->second);
      pairs.push_back(pair);
    }
    return it->second;
  }

  // Reaches every pair `start` needs that no earlier question reached, then
  // takes the greatest fixpoint over them. A pair reached earlier is
  // settled: everything it needs was reached and settled with it.
  void solve(Pair start) {
    SmallVector<unsigned> fresh;
    nodeOf(start, fresh);
    SmallVector<unsigned> broken;
    for (size_t next = 0; next < fresh.size(); ++next) {
      unsigned id = fresh[next];
      std::optional<SmallVector<Pair>> needs =
          fresh.size() > pairLimit ? std::nullopt : needsOf(pairs[id]);
      if (!needs) {
        nodes[id].state = State::Broken;
        broken.push_back(id);
        continue;
      }
      for (Pair need : *needs) {
        unsigned other = nodeOf(need, fresh);
        nodes[id].needs.push_back(other);
        nodes[other].neededBy.push_back(id);
      }
    }
    for (unsigned id : fresh)
      if (nodes[id].state == State::Open &&
          llvm::any_of(nodes[id].needs, [&](unsigned n) { return nodes[n].state == State::Broken; })) {
        nodes[id].state = State::Broken;
        broken.push_back(id);
      }
    while (!broken.empty()) {
      unsigned id = broken.pop_back_val();
      for (unsigned user : nodes[id].neededBy)
        if (nodes[user].state == State::Open) {
          nodes[user].state = State::Broken;
          broken.push_back(user);
        }
    }
    for (unsigned id : fresh)
      if (nodes[id].state == State::Open)
        nodes[id].state = State::Held;
  }

  Calls calls;
  DataFlowSolver &solver;
  DominanceInfo dominance;
  DenseMap<Pair, unsigned> index;
  SmallVector<Pair> pairs;
  SmallVector<Node> nodes;
  DenseMap<Pair, bool> clampCache;
  DenseSet<Pair> clampOpen;
};

} // namespace idr::inbounds
