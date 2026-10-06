// idr.inbounds:lengths: which integers are the lengths of which arrays.
// `related(n, a)` holds when, wherever `n` and `a` are both in scope, the
// array `a` has `max(n, 0)` elements: what `idr.array.new %n` gives, and
// what the program then carries apart, a record of a size and an array
// taken apart into two parameters or two loop arguments.
//
// The relation of a pair is decided by where its values come from. An
// array made of a size relates to that size. A pair bound at one join (two
// arguments of one function, of one loop, two results of one region op or
// call) is related when every place binding them gives a related pair; a
// value bound at a join and one fixed around it (a size defined before the
// loop that carries the array) when every place gives a value related to
// the fixed one. Pairs reach each other in cycles (a loop gives back what
// it took), so the answer is the greatest fixpoint: every pair reached is
// taken to hold, and each that needs a pair that fails, or that comes from
// anything else, fails, until none changes. What remains holds by
// induction over the run: each binding of a pair that holds is made of
// pairs that held. A poison array is no array any access may read, so it
// relates to every size; a poison size relates to no array, since an
// access that never branches on it would read the array unchecked.
export module idr.inbounds:lengths;

import idr.mlir;
import idr.dialect;

import :joins;

using namespace mlir;

namespace idr::inbounds {

namespace {

// Past this many pairs reached from one question, the rest fail: an
// answer is then only weaker.
constexpr size_t pairLimit = 4096;

int64_t clamped(const APInt &size) { return std::max<int64_t>(size.getSExtValue(), 0); }

} // namespace

export class Lengths {
public:
  explicit Lengths(ModuleOp module) : calls(module) {}

  // Whether the array `array` has `size` clamped at 0 elements wherever
  // both are in scope.
  bool related(Value size, Value array) {
    Pair start{size, arrayRoot(array)};
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

  // The pairs `pair` holds by, all needed; none when it cannot hold.
  std::optional<SmallVector<Pair>> needsOf(Pair pair) {
    auto [size, array] = pair;
    if (array.getDefiningOp<ub::PoisonOp>())
      return SmallVector<Pair>{};
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
    if (auto fresh = array.getDefiningOp<ArrayNewOp>())
      made = fresh.getSize();
    else if (auto generated = array.getDefiningOp<ArrayGenerateOp>())
      made = generated.getSize();
    if (!made)
      return std::nullopt;
    if (made == size)
      return needs;
    APInt a, b;
    if (matchPattern(size, m_ConstantInt(&a)) && matchPattern(made, m_ConstantInt(&b)) &&
        clamped(a) == clamped(b))
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
  DominanceInfo dominance;
  DenseMap<Pair, unsigned> index;
  SmallVector<Pair> pairs;
  SmallVector<Node> nodes;
};

} // namespace idr::inbounds
