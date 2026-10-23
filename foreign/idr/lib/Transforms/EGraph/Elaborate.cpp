// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Extraction and the writing back of one function.
//
// Extraction takes each class's cheapest member by the engine's own cost,
// an op one and a constant none, until a measured model replaces it,
// among the members computable in the class's reach. Every use of a class
// is in its reach, so such a member is computable at each use, and its
// operands' reaches hold it, so theirs are too.
//
// A class may hold a member that reads the class itself, so prices are
// relaxed: passes over every node in creation order, each pricing a node
// whose operands are priced and moving its class to it where it costs
// less, until a pass moves none, and at most one pass per class. The best
// form of a class never reads one class twice down a path, since going
// round a cycle costs more, so each pass carries it at least one class
// further and the passes are enough.
//
// Elaboration goes through the regions in program order, a region's ops
// before the op after the region op that holds it, on an explicit stack.
// Before each skeleton op its operands are demanded where it is: a class
// placed in this scope or an enclosing one is that value; any other is
// made there, its operands first, so a value is computed in each scope
// that needs it and never above a match that does not. The skeleton's
// edits are carried out as their ops are reached. Then every floating op
// left unused is erased (sweep), and every call takes the tail fact its new
// place gives it. The placements and the regions' stack are the
// footprint's; a demand's postorder is the shared depth-first walk's.
//
// A demand is of a class at a use, and the use decides how it takes the
// class. A string or a big the graph computed stands as an idr.constant
// only at a static hold (fold::constantStandsAt), and the class it is the
// value of may be typed at a hold that counts, as the frontend types what a
// primitive makes. Static data stands where a hold that claims nothing is
// asked, by the grade order, so such a class has a static form, its type
// with its hold made static (staticFormOf). A use whose op's own rule takes
// any value whose hold claims nothing takes the static data: an operand the
// op's runtime function borrows, and a field of a constructor (fillsField,
// the one rule of what a field holds). Neither gives the operand on in a
// result: the function's result is its own fresh value, and the
// constructor's cell is fresh, its claim, read off its fields, the same of
// static data as of a value that claims nothing; so nothing after the use
// is regraded. Every other use takes the class at its own type, the op that
// computes it applied there: a call, whose callee's signature fixes its
// grades exactly, and whose copy keyed by a static hold only a later round
// of the optimizer would make, while a round that only simplified is a
// function's last and the pipeline's own runs of the graph have no
// specializer after them; a return, whose grades the function's signature
// fixes; a yield, whose types its parent's results fix; and an op whose
// result carries the value on: a cast, which would stand static data at a
// hold that counts, and a guard, whose result's uses ask the value's own
// type. An edit's operands become its results or its region's arguments,
// read at their own types, so they are demanded at their own types too;
// and what the edit replaced becomes the class it is given, so where the
// graph removed an op that carries a value on (a guard decided to hold, a
// match whose one region is taken), the uses after it demand that value's
// class, each taking its static data as it takes the value.
#include "idr/Transforms/EGraph/Engine.h"

#include "idr/IR/Tail.h"
#include "idr/Support/Nest.h"
#include "idr/Transforms/Optimize/Tails.h"

#include "llvm/ADT/STLExtras.h"

#include <cassert>

using namespace mlir;

namespace idr::egraph::detail {

namespace {

// The engine's own cost: an op one, an atom, which is placed for nothing,
// none.
Cost ownCost(const Node &node) {
  return match(node.what, []<Atom N>(const N &) { return Cost::of(0); },
               [](const OneOf<node::Input, node::Built> auto &) { return Cost::of(1); });
}

// How a use takes a class whose type asks a hold that claims nothing: as
// the static data that stands for it, where its op's rule takes any such
// value, or only at the class's own type.
enum class Admits : std::uint8_t { StaticData, OwnType };

// Whether `operand` is one of the fields a constructor is built of.
bool isField(const structural::Built &built, unsigned operand) {
  if (built.fields.empty())
    return false;
  unsigned first = built.fields.getBeginOperandIndex();
  return operand >= first && operand - first < built.fields.size();
}

// How the use `operand` of `op`, an op of the input, takes such a class: as
// static data where the op's runtime function borrows it, or where the op
// builds a constructor of which it is a field; at its own type anywhere
// else.
Admits admitsAt(const Kinds &kinds, Operation *op, unsigned operand) {
  if (kinds.of(op).borrowed.has(operand))
    return Admits::StaticData;
  auto structure = dyn_cast<StructureOpInterface>(op);
  if (!structure)
    return Admits::OwnType;
  return match(
      structure.getStructure(),
      [&](const structural::Built &built) {
        return isField(built, operand) ? Admits::StaticData : Admits::OwnType;
      },
      [](const OneOf<structural::Unbuilt, structural::Successor, structural::Predecessor> auto &) {
        return Admits::OwnType;
      });
}

// The same of the op a chosen member writes back: an op of the input's own;
// a rule's right side builds no constructor, since a rule makes nothing
// with an identity, so a built op's is its kind's row alone. An atom reads
// no class, so no use of one is asked.
Admits admitsAt(const Kinds &kinds, const Node &user, unsigned operand) {
  return match(
      user.what, [&](const node::Input &op) { return admitsAt(kinds, op.origin, operand); },
      [&](const node::Built &op) {
        return kinds.of(op.name.getTypeID()).borrowed.has(operand) ? Admits::StaticData
                                                                   : Admits::OwnType;
      },
      []<Atom N>(const N &) { return Admits::OwnType; });
}

// What a use demands of a class: its value at the class's own type, or the
// static data that stands for it at `type`, the class's static form.
struct AtOwnType {
  ClassId cls;
};
struct AsStaticData {
  ClassId cls;
  Type type;
};
using Wanted = std::variant<AtOwnType, AsStaticData>;

} // namespace

// A class moves to a member only for a lower price, or for an equal price
// and a larger id, the newer form a rule's side built, while the price is
// below the cost's saturation. An op costs at least one, so a member chosen
// costs more than each class it reads; a move to a member reading a class
// that leads back to this one would raise its price, which no move does:
// so the chosen members close no cycle, and the demand's walk over them
// ends. Every node is settled at its class's root.
void Function::extract() {
  best.assign(classes.size(), std::nullopt);
  cost.assign(classes.size(), Cost::most());
  for (std::uint32_t pass = 0; pass < classes.size(); ++pass) {
    Changed moved = Changed::No;
    for (std::uint32_t n = 0; n < nodes.size(); ++n) {
      ++steps;
      NodeId member(n);
      const Node &node = at(member);
      std::uint32_t c = classOfNode(member).index();
      // A member computable only inside its class's reach is not computable
      // at every use of the class.
      if (needs(node) != classes[c].reach)
        continue;
      std::span<const ClassId> operands = childrenOf(node);
      auto priced = [&](ClassId operand) { return best[operand.index()].has_value(); };
      if (!llvm::all_of(operands, priced))
        continue;
      Cost total = ownCost(node);
      for (ClassId operand : operands)
        total = total.plus(cost[operand.index()]);
      if (best[c] && !(total < cost[c] ||
                       (total == cost[c] && total < Cost::most() && *best[c] < member)))
        continue;
      best[c] = member;
      cost[c] = total;
      moved = Changed::Yes;
    }
    if (moved == Changed::No)
      break;
  }
  for (std::uint32_t c = 0; c < classes.size(); ++c)
    assert((!forest.isRoot(ClassId(c)) || best[c]) && "every class has a member priced");
}

void Function::elaborate(RewriterBase &rewriter) {
  // The dialect whose constant op holds a string or a big, found once.
  Dialect &constants = *rewriter.getContext()->getLoadedDialect<IdrDialect>();

  // The static form of each class the graph knows as a string or a big its
  // constant op does not stand at, read once before any use asks.
  footprint::Vector<std::optional<Type>> statics(classes.size());
  for (std::uint32_t c = 0; c < classes.size(); ++c) {
    const Class &cls = classes[c];
    if (forest.isRoot(ClassId(c)) && cls.facts.constant &&
        !placedAt(*cls.facts.constant, cls.type))
      statics[c] = staticFormOf(*cls.facts.constant, cls.type);
  }
  // What each class an edit replaced has become: the class of the value a
  // forwarded result, a taken region's argument or a taken op's result is
  // given. So each later use demands that class, as the use takes it, the
  // static data that stands for it included, and never a value the edit
  // erased. Each edit links a class not yet replaced to one that is not
  // either, and the two differ, so a chain of them ends.
  footprint::Vector<std::optional<ClassId>> becomes(classes.size());
  auto current = [&](ClassId c) {
    for (std::optional<ClassId> next = becomes[c.index()]; next; next = becomes[next->index()])
      c = *next;
    return c;
  };
  // What a use of `c` demands: the static data, where the class it now is
  // has a static form and the use takes it so; else that class at its own
  // type.
  auto wanted = [&](ClassId c, Admits admits) -> Wanted {
    ClassId now = current(c);
    const std::optional<Type> &form = statics[now.index()];
    if (form && admits == Admits::StaticData)
      return AsStaticData{now, *form};
    return AtOwnType{now};
  };

  // Where each class is placed so far, at its own type and as static data:
  // a scope and its value there.
  using Placements = footprint::Vector<std::pair<RegionId, Value>>;
  footprint::Vector<Placements> placed(classes.size());
  footprint::Vector<Placements> placedStatic(classes.size());
  auto placedIn = [&](const Wanted &want, RegionId scope) -> std::optional<Value> {
    auto seenFrom = [&](const Placements &places) -> std::optional<Value> {
      for (auto [region, value] : places) {
        ++steps;
        if (visible(region, scope))
          return value;
      }
      return std::nullopt;
    };
    return match(
        want,
        [&](const AtOwnType &own) -> std::optional<Value> {
          if (std::optional<Value> value = seenFrom(placed[own.cls.index()]))
            return value;
          // A leaf is where it is, and is chosen only for a class whose
          // reach is its region, which holds every scope that demands the
          // class; anything else is made there.
          return match(
              at(*best[own.cls.index()]).what,
              [](const node::Leaf &leaf) -> std::optional<Value> { return leaf.value; },
              [](const OneOf<node::Held, node::Integer, node::Known, node::Input,
                             node::Built> auto &) -> std::optional<Value> { return std::nullopt; });
        },
        // Static data is an atom, made in each scope that demands it.
        [&](const AsStaticData &data) { return seenFrom(placedStatic[data.cls.index()]); });
  };

  // The value `root` demands where `scope` demands it, made before the
  // rewriter's insertion point where it is not yet there: a postorder over
  // the chosen members, which goes past a demand `scope` already sees and
  // makes each other one once what it reads is made. The chosen members
  // form a DAG, so a class shared by two operands is made by the first and
  // seen by the second.
  auto demand = [&](const Wanted &root, RegionId scope, Location loc) -> Value {
    // What a demand reads: each operand of the class's chosen member, as the
    // member's op takes it; static data reads nothing.
    auto readsOf = [&](const Wanted &want) {
      return match(
          want,
          [&](const AtOwnType &own) {
            const Node &node = at(*best[own.cls.index()]);
            SmallVector<Wanted, 4> reads;
            for (auto [index, operand] : llvm::enumerate(childrenOf(node)))
              reads.push_back(wanted(operand, admitsAt(kinds, node, static_cast<unsigned>(index))));
            return reads;
          },
          [](const AsStaticData &) { return SmallVector<Wanted, 4>(); });
    };
    auto seen = [&](const Wanted &want) {
      return placedIn(want, scope) ? Descend::Past : Descend::Into;
    };
    auto make = [&](const Wanted &want) {
      match(
          want,
          [&](const AtOwnType &own) {
            const Node &node = at(*best[own.cls.index()]);
            SmallVector<Value, 4> values;
            for (const Wanted &read : readsOf(want))
              values.push_back(*placedIn(read, scope));
            // A constant an op holds is materialized by its dialect, the
            // attribute it held; a constant the graph knows gets its
            // attribute here, the one place the graph makes one; an op of the
            // input is copied, its properties with it, and given what it
            // reads operand by operand, as its uses demand it; a built one is
            // made of its kind's op with the op's default properties; a leaf
            // is where it is.
            Value made = match(
                node.what, [](const node::Leaf &leaf) -> Value { return leaf.value; },
                [&](const node::Held &literal) -> Value {
                  return materialized(*literal.dialect, rewriter, loc, node.type, literal.value);
                },
                [&](const node::Integer &integer) -> Value {
                  return writeBack(rewriter, loc, node.type, integer, constants);
                },
                [&](const node::Known &known) -> Value {
                  return writeBack(rewriter, loc, node.type, known.value, constants);
                },
                [&](const node::Input &op) -> Value {
                  Operation *copy = rewriter.clone(*op.origin);
                  copy->setOperands(values);
                  return copy->getResult(0);
                },
                [&](const node::Built &op) -> Value {
                  OperationState state(loc, op.name);
                  state.addOperands(values);
                  state.addTypes(node.type);
                  return rewriter.create(state)->getResult(0);
                });
            placed[own.cls.index()].emplace_back(scope, made);
          },
          [&](const AsStaticData &data) {
            Value made = writeBack(rewriter, loc, data.type,
                                   *classes[data.cls.index()].facts.constant, constants);
            placedStatic[data.cls.index()].emplace_back(scope, made);
          });
    };
    depthFirst(root, readsOf, seen, make);
    return *placedIn(root, scope);
  };

  // The class each skeleton op's operand names, read off the input before
  // any edit replaces a value: an op met after an edit reads its operands by
  // their classes, never by a value the edit put in their place, which the
  // numbering never saw.
  footprint::Vector<ClassId> operandClasses;
  footprint::Vector<Run> operandRuns;
  operandRuns.reserve(skeleton.size());
  for (const Skeletal &entry : skeleton) {
    operandRuns.push_back({static_cast<std::uint32_t>(operandClasses.size()),
                           entry.op->getNumOperands()});
    for (Value operand : entry.op->getOperands())
      operandClasses.push_back(*classOf[numbering.at(operand)]);
  }
  // `replaced`, a value of the input an edit erases, becomes `by`'s class.
  auto become = [&](Value replaced, ClassId by) {
    ClassId from = current(*classOf[numbering.at(replaced)]);
    ClassId to = current(by);
    if (from != to)
      becomes[from.index()] = to;
  };

  // One region's skeleton, written back in `scope`: a region's own, or, for
  // a region a Take moved into its op's place, the op's, whose terminator
  // gives the taken op its results.
  struct Frame {
    Run skeleton;
    std::uint32_t next;
    RegionId scope;
    Operation *taken;
  };
  // The function's body is the first region the build numbered.
  RegionId body = RegionId(0);
  footprint::Vector<Frame> stack{{at(body).skeleton, 0, body, nullptr}};
  auto regionAt = [&](const Skeletal &entry, unsigned index) {
    return RegionId(entry.regions->index() + index);
  };
  auto pushRegions = [&](const Skeletal &entry) {
    for (unsigned index = entry.op->getNumRegions(); index-- > 0;) {
      RegionId id = regionAt(entry, index);
      stack.push_back({at(id).skeleton, 0, id, nullptr});
    }
  };

  while (!stack.empty()) {
    Frame &frame = stack.back();
    if (frame.next == frame.skeleton.count) {
      stack.pop_back();
      continue;
    }
    std::uint32_t place = frame.skeleton.first + frame.next++;
    Skeletal entry = skeleton[place];
    RegionId scope = frame.scope;
    Operation *taken = frame.taken;
    Operation *op = entry.op;

    // An op that stays as it is takes each operand as its own rule says;
    // one an edit replaces gives its operands on as its results or its
    // region's arguments, read at their own types, and one merged into an
    // earlier op is gone. The last turn decides no Rewrite: its rewrites
    // ran between the turns.
    auto admits = [&](unsigned index) {
      return match(
          entry.fate, [&](const Kept &) { return admitsAt(kinds, op, index); },
          [](const OneOf<Merged, Decided> auto &) { return Admits::OwnType; });
    };
    rewriter.setInsertionPoint(op);
    Run run = operandRuns[place];
    SmallVector<Value, 4> operands;
    for (unsigned index = 0; index < run.count; ++index)
      operands.push_back(
          demand(wanted(operandClasses[run.first + index], admits(index)), scope, op->getLoc()));
    if (!llvm::equal(operands, op->getOperands()))
      rewriter.modifyOpInPlace(op, [&] { op->setOperands(operands); });

    // The terminator of a region a Take moved: what it yields is the taken
    // op's results.
    if (taken && op->hasTrait<OpTrait::IsTerminator>()) {
      assert(run.count == taken->getNumResults() && "a taken region yields its op's results");
      for (auto [index, result] : llvm::enumerate(taken->getResults()))
        become(result, operandClasses[run.first + index]);
      rewriter.replaceOp(taken, operands);
      rewriter.eraseOp(op);
      continue;
    }

    match(
        entry.fate, [&](const Kept &) { pushRegions(entry); },
        [&](const Merged &merged) { rewriter.replaceOp(op, merged.into->getResults()); },
        [&](const Decided &decided) {
          match(
              decided.edit,
              [&](const Forward &forward) {
                SmallVector<Value, 2> results;
                for (auto [result, operand] :
                     llvm::zip_equal(op->getResults(), forward.operandOfResult)) {
                  become(result, operandClasses[run.first + operand]);
                  results.push_back(operands[operand]);
                }
                rewriter.replaceOp(op, results);
              },
              [&](const Take &take) {
                mlir::Region &region = op->getRegion(take.region);
                Block &block = region.front();
                SmallVector<Value, 2> arguments;
                for (auto [argument, operand] :
                     llvm::zip_equal(block.getArguments(), take.operandOfArgument)) {
                  become(argument, operandClasses[run.first + operand]);
                  arguments.push_back(operands[operand]);
                }
                RegionId moved = regionAt(entry, take.region);
                rewriter.inlineBlockBefore(&block, op, arguments);
                stack.push_back({at(moved).skeleton, 0, scope, op});
              },
              [&](const Rewrite &) { pushRegions(entry); });
        });
  }

  sweep(rewriter);

  // What follows a call is new wherever a floating op followed it, since
  // every one was made again where it is demanded and the input's erased;
  // a call that floated was made again itself, and an edit or a merge
  // erased the op it stood for, an op that holds no fact of where it stood.
  // So a call may now end a tail, or its result flow into cells built for
  // it: the function was written back whole, and its calls take their
  // facts off its tails, once. Before the program is first order its calls
  // promise nothing, and no pass writes one.
  if (tail::decided(fn))
    (void)optimize::decideTails(fn);
}

} // namespace idr::egraph::detail
