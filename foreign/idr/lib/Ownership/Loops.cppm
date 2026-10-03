// idr.ownership:loops: the scf loops idr-tail-loops makes, as the walk of a
// function in the owned stage follows the references through them. Nothing
// here is exported: the owned stage's checker is built on it.
export module idr.ownership:loops;

import idr.mlir;
import idr.dialect;

import :references;

using namespace mlir;

namespace idr::ownership {

class Loops : public References {
public:
  using References::References;
  virtual ~Loops() = default;

protected:
  // Walks `block` from the current state, as the checker does. Returns
  // whether its end is reached, or failure after reporting a violation.
  virtual FailureOr<bool> walk(Block &block) = 0;

  // The borrowed value a slot of a loop carries on its first iteration, or
  // null when the slot is owned.
  Value slotOwner(Operation *loop, unsigned slot) {
    auto it = loops.find(loop);
    if (it == loops.end() || slot >= it->second.size())
      return Value();
    return it->second[slot];
  }

  // A borrowed slot's value reaches the loop's scf.condition through the
  // matches idr-tail-loops builds on the way, which pass it on borrowed.
  void passOn(Value value, Value owner) {
    auto result = dyn_cast<OpResult>(value);
    if (!result || !isa<MatchOp, MatchLitOp>(result.getOwner()))
      return;
    passedOn[value] = owner;
    for (Region &region : result.getOwner()->getRegions())
      if (!region.empty())
        if (auto yield = dyn_cast<YieldOp>(region.front().getTerminator()))
          passOn(yield.getOperand(result.getResultNumber()), owner);
  }

  // An scf.while of idr-tail-loops, which carries a function's parameters
  // first, then its results. A slot whose first value is a view (a
  // borrowed parameter) carries views, which live as long as that first
  // one; every other carried slot's values are owned: the initial values
  // are consumed, each region takes its arguments owned and consumes what
  // its terminator passes on, and leaves the values from outside as it
  // found them. The condition passes on, beyond the carried slots, the
  // views the rest of the body needs of the before region's work (the
  // scrutinee it read); each is a view of a carried slot's value, and
  // lives as long as that slot's value on the other side, or of a value
  // from outside the loop. The results and the after region's arguments
  // that nothing uses are the payload of the path not taken, which is
  // poison there.
  FailureOr<bool> walkLoop(scf::WhileOp loop) {
    Operation &op = *loop.getOperation();
    SmallVector<Value> &slots = loops[loop];
    auto carried = static_cast<unsigned>(loop.getInits().size());
    for (Value init : loop.getInits()) {
      bool borrowed = isView(init);
      slots.push_back(borrowed ? init : Value());
      if (failed(borrowed ? use(op, init) : consume(op, init)))
        return failure();
    }
    scf::ConditionOp condition;
    if (!loop.getBefore().empty())
      condition = dyn_cast<scf::ConditionOp>(loop.getBefore().front().getTerminator());
    if (condition)
      for (auto [slot, value] : llvm::enumerate(condition.getArgs()))
        if (Value owner = slotOwner(loop, static_cast<unsigned>(slot)))
          passOn(value, owner);
    // What each view passed on beyond the carried slots is a view of, known
    // once the before region is walked.
    SmallVector<std::variant<unsigned, Value>> passed;
    auto slotType = [&](unsigned slot, Value value, ValueRange side, bool after) {
      if (Value owner = slotOwner(loop, slot)) {
        define(value, 0, owner, /*borrowed=*/true);
      } else if (slot >= carried && slot - carried < passed.size() && isView(value)) {
        const auto &of = passed[slot - carried];
        define(value, 0, std::holds_alternative<unsigned>(of) ? side[std::get<unsigned>(of)] : std::get<Value>(of),
               /*borrowed=*/true);
      } else if (tracked(value)) {
        define(value, after && value.use_empty() ? 0 : 1);
      }
    };
    size_t mark = log.size();
    bool exits = false;
    for (Region *region : {&loop.getBefore(), &loop.getAfter()}) {
      if (region->empty())
        continue;
      Block &block = region->front();
      bool after = region == &loop.getAfter();
      for (BlockArgument arg : block.getArguments())
        slotType(arg.getArgNumber(), arg, block.getArguments(), after);
      FailureOr<bool> reached = walk(block);
      if (failed(reached))
        return failure();
      if (*reached) {
        if (failed(settled(block, block.back())))
          return failure();
        auto changes = changesSince(mark);
        if (!changes.empty())
          return fail(op, changes.front().first,
                      "changes the references of a value from outside the loop in its body");
        exits = exits || !after;
      }
      if (!after && condition)
        for (Value value : condition.getArgs().drop_front(carried))
          passed.push_back(viewOf(value, block));
      undo(mark);
    }
    for (OpResult result : loop.getResults())
      slotType(result.getResultNumber(), result, loop.getResults(), /*after=*/true);
    return exits;
  }

  // What a view the before region of a loop passes on is a view of: the
  // carried slot whose value it was read from, or a value from outside the
  // loop (null for a borrowed parameter, which is alive throughout).
  std::variant<unsigned, Value> viewOf(Value value, Block &before) {
    for (unsigned depth = 0; depth < 1024; ++depth) {
      if (auto arg = dyn_cast<BlockArgument>(value); arg && arg.getOwner() == &before)
        return arg.getArgNumber();
      auto owner = owners.find(value);
      if (owner == owners.end())
        return value;
      if (!owner->second)
        return Value();
      value = owner->second;
    }
    return value;
  }

  // An scf.for that idr-tail-loops made of a counted scf.while: its slots
  // are the iteration arguments, borrowed or owned as a while loop's, and
  // its body is the after region, which always reaches its yield or ends
  // the program.
  FailureOr<bool> walkFor(scf::ForOp loop) {
    Operation &op = *loop.getOperation();
    for (Value bound : {loop.getLowerBound(), loop.getUpperBound(), loop.getStep()})
      if (failed(use(op, bound)))
        return failure();
    SmallVector<Value> &slots = loops[loop];
    for (Value init : loop.getInitArgs()) {
      bool borrowed = isView(init);
      slots.push_back(borrowed ? init : Value());
      if (failed(borrowed ? use(op, init) : consume(op, init)))
        return failure();
    }
    auto slotType = [&](unsigned slot, Value value, bool result) {
      if (Value owner = slotOwner(loop, slot))
        define(value, 0, owner, /*borrowed=*/true);
      else if (tracked(value))
        define(value, result && value.use_empty() ? 0 : 1);
    };
    size_t mark = log.size();
    Block &body = *loop.getBody();
    for (BlockArgument arg : loop.getRegionIterArgs())
      slotType(arg.getArgNumber() - loop.getNumInductionVars(), arg, /*result=*/false);
    FailureOr<bool> reached = walk(body);
    if (failed(reached))
      return failure();
    if (*reached) {
      if (failed(settled(body, body.back())))
        return failure();
      auto changes = changesSince(mark);
      if (!changes.empty())
        return fail(op, changes.front().first,
                    "changes the references of a value from outside the loop in its body");
    }
    undo(mark);
    for (OpResult result : loop.getResults())
      slotType(result.getResultNumber(), result, /*result=*/true);
    return true;
  }

  // For each loop, the owner of each borrowed slot.
  llvm::DenseMap<Operation *, SmallVector<Value>> loops;
  // The match results that pass a borrowed slot on, with its owner.
  llvm::DenseMap<Value, Value> passedOn;
};

} // namespace idr::ownership
