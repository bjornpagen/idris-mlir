// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The local rule of exclusivity: what QTT and freshness prove of a value's
// sharing from its definition alone. A value is unique where it is fresh (a
// constructor's, a recycled cell's, or a call's result whose signature says
// so) or taken or read at a linear position from one that is, and it is used
// once. Each op states its part in the edges it declares (FlowEdges.h), so
// the rule names no op: a fresh value claims the most whose read of each part
// moved into it gives no more than the part claims, and nothing beyond its
// own cells of a part every slot of an array holds; a value moved on claims
// what was moved, and one made new by a whole moved into it its own cells
// besides; a part read or taken out claims what the grade's read of it gives
// (Hold::read), except a capture moved out of a memo label's field, which
// holds what the label's field held; a copy, a constant and a value no edge
// explains claim nothing. A value used many times claims nothing before
// references are counted (the program's stage rule), so what it gives is its
// type's at every stage, except to a cast that enters it into a position as
// its one use, every other use of what holds its cell a read that ends
// before the cast, which carries what that cell holds (entryOf: a region's
// argument entered from one place holds the cell of the value entered).
//
// Two readers instantiate it. The verifier holds every value that claims
// anything of its sharing to it, one op at a time, each source's claim its
// type's (LocalCheck, a rule of the function's one walk). idr-unique-results
// solves it over each body before bufferization, each call's result its
// callee's derived claim, each entering cast what its cell's source is
// solved to, and writes what it proves into the types; the exclusivity
// marking after bufferization covers only what this rule cannot prove.
#ifndef IDR_ANALYSIS_OWNERSHIP_LOCAL_H
#define IDR_ANALYSIS_OWNERSHIP_LOCAL_H

#include "idr/Analysis/Ownership/Facts.h"
#include "idr/IR/Families/Scope.h"
#include "idr/IR/Flow.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Match.h"

#include "mlir/IR/Operation.h"
#include "mlir/IR/Region.h"
#include "mlir/IR/Value.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/STLExtras.h"

#include <algorithm>
#include <concepts>
#include <cstdint>
#include <optional>
#include <type_traits>
#include <variant>

namespace idr::ownership {

// The claims in their order: nothing, the own cells, everything reached.
constexpr bool covers(Unique held, Unique asked) {
  return static_cast<unsigned>(held) >= static_cast<unsigned>(asked);
}
constexpr Unique lesser(Unique a, Unique b) { return covers(a, b) ? b : a; }
constexpr Unique greater(Unique a, Unique b) { return covers(a, b) ? a : b; }

// The most a fresh value may claim, built of a part reached as `reach` that
// claims `given`: the greatest claim whose read of the part at one use, the
// read that gives most, gives no more than the part holds. A part outside
// the value's own cells bounds only a deep claim. Read from the
// specification's table of it (freshestClaims), its freshClaim's fold.
constexpr Unique freshest(FieldReach reach, Unique given) {
  return freshestClaims[static_cast<unsigned>(reach)][static_cast<unsigned>(given)];
}

// How a value is given what its source holds, as an edge into it says.
enum class Via : std::uint8_t {
  // The source's use taken over whole, or forwarded: what the source
  // claims; into a value the op makes new, its own cells besides.
  Moved,
  // Read and not given up, or a constant: shared with whatever else holds it.
  Copied,
  // A part read or taken out of the source: what the source's claim reads
  // there.
  ReadOut,
  // Moved into a part of the value the op builds: the value may claim
  // what that part bounds.
  Built,
  // A part of the value the op builds filled by what the op does not take
  // over, or by what every slot of it holds: a value read, or one spread
  // over the slots, shared; or a hole another op writes, holding what its
  // destination's type bounds the write to (`held`).
  Filled,
  // Moved out of a memo label's field, its place emptied: what every init
  // moved into the label's field, which only the marking follows across the
  // program.
  Anchored,
  // Read out of a slot whose own type states what it holds (a hole, whose
  // destination's type bounds the write that fills it): that claim.
  Slot,
};

// One term of a value's claim: its source (unused for Copied, Filled and
// Slot), how the value is given it, how far a claim reaches into the part
// it is read out of or built into, at how many uses a part is read out
// (the read value's own: a read at a linear position gives what the claim
// reaches, any other nothing), and, for a slot or a part a hole fills,
// what the slot's type claims.
template <class Source>
struct Term {
  Source from;
  Via via;
  FieldReach reach;
  Uses uses = Uses::Once;
  Unique held = Unique::None;
};

// Whether an op makes the value new, or the value is moved into from
// elsewhere, or no edge of the op explains it.
enum class Origin : std::uint8_t { Unexplained, Fresh, Flows };

// Whether the op that makes a value declares it new (a Fresh edge).
enum class Made : std::uint8_t { Elsewhere, New };

// Each term of a value among `edges`, an op's declared edges, handed to
// `term(target, Term<Value>)`, and each value the op makes new to
// `fresh(target)`. Only edges that carry a reference are read; a parameter
// or a result is a call's, which the reader reads from the call. A target
// may be a value the op writes in place rather than makes; a reader keeps
// the terms of the values the op makes (its results and its regions'
// arguments).
template <std::invocable<mlir::Value, const Term<mlir::Value> &> OnTerm,
          std::invocable<mlir::Value> OnFresh>
void forEachTerm(const FlowEdges &edges, OnTerm &&term, OnFresh &&fresh) {
  for (const FlowEdges::Edge &edge : edges.edges())
    match(
        edge.move,
        [&](const FlowEdges::Fresh &made) {
          if (edge.carries(Carrier::Reference))
            fresh(made.to);
        },
        [&](const FlowEdges::Constant &constant) {
          if (edge.carries(Carrier::Reference))
            term(constant.to, Term<mlir::Value>{mlir::Value(), Via::Copied, FieldReach::Other});
        },
        [&](const FlowEdges::Flow &flow) {
          if (!edge.carries(Carrier::Reference))
            return;
          match(
              flow.to.at,
              [&](const FlowSource::Whole &into) {
                match(
                    flow.from.at,
                    [&](const FlowSource::Taken &taken) {
                      term(into.value, Term<mlir::Value>{taken.use->get(), Via::Moved,
                                                         FieldReach::Other});
                    },
                    [&](const FlowSource::Whole &read) {
                      term(into.value, Term<mlir::Value>{read.value, Via::Copied,
                                                         FieldReach::Other});
                    },
                    [&](const FlowSource::Part &part) {
                      mlir::Value whole = *flow.from.value();
                      match(
                          part.anchor.place,
                          [&](const FlowAnchor::Hole &hole) {
                            term(into.value,
                                 Term<mlir::Value>{whole, Via::Slot, FieldReach::Other,
                                                   Uses::Once, claimOf(hole.dest.getValue())});
                          },
                          [&](const FlowAnchor::Field &field) {
                            bool memo = field.group.memberKind(field.member) == MemberKind::Memo;
                            Via via = memo && placeAfter(edges, part) == PlaceAfter::Emptied
                                          ? Via::Anchored
                                          : Via::ReadOut;
                            term(into.value, Term<mlir::Value>{whole, via, reachAt(part.anchor),
                                                               usesOf(into.value.getType())});
                          },
                          [&](const OneOf<FlowAnchor::Elements, FlowAnchor::Forced,
                                          FlowAnchor::MemoState, FlowAnchor::Capture> auto &) {
                            term(into.value,
                                 Term<mlir::Value>{whole, Via::ReadOut, FieldReach::Other,
                                                   usesOf(into.value.getType())});
                          });
                    },
                    [](const FlowSource::Parameter &) {}, [](const FlowSource::Result &) {});
              },
              [&](const FlowPlace::Part &into) {
                mlir::Value built = into.of;
                FieldReach reach = reachAt(into.anchor);
                match(
                    flow.from.at,
                    // Essential, the two ways a flow fills: one place, which
                    // what is taken over bounds as a part; or every slot of
                    // the part, each reaching what fills them, so it bounds
                    // the value as a shared one does.
                    [&](const FlowSource::Taken &taken) {
                      if (flow.fills == FlowEdges::Fills::EverySlot)
                        term(built, Term<mlir::Value>{mlir::Value(), Via::Filled, reach});
                      else
                        term(built, Term<mlir::Value>{taken.use->get(), Via::Built, reach});
                    },
                    [&](const NotTaken auto &) {
                      term(built, Term<mlir::Value>{mlir::Value(), Via::Filled, reach});
                    });
              },
              [](const FlowSource::Parameter &) {}, [](const FlowSource::Result &) {});
        },
        // A part of a value the op builds that it joins to another place,
        // a hole another op writes: what fills it is what the hole's
        // destination's type bounds, and anything where the place is no hole.
        [&](const FlowEdges::Unify &unify) {
          auto holds = [](const FlowPlace &place) {
            return match(
                place.at,
                [](const FlowPlace::Part &part) {
                  return match(
                      part.anchor.place,
                      [](const FlowAnchor::Hole &hole) { return claimOf(hole.dest.getValue()); },
                      [](const OneOf<FlowAnchor::Field, FlowAnchor::Elements, FlowAnchor::Forced,
                                     FlowAnchor::MemoState, FlowAnchor::Capture> auto &) {
                        return Unique::None;
                      });
                },
                [](const WholePlace auto &) { return Unique::None; });
          };
          auto filled = [&](const FlowPlace &place, const FlowPlace &other) {
            match(
                place.at,
                [&](const FlowPlace::Part &part) {
                  term(part.of, Term<mlir::Value>{mlir::Value(), Via::Filled, reachAt(part.anchor),
                                                  Uses::Once, holds(other)});
                },
                [](const WholePlace auto &) {});
          };
          filled(unify.a, unify.b);
          filled(unify.b, unify.a);
        },
        [](const FlowEdges::Source &) {}, [](const FlowEdges::Release &) {},
        [](const FlowEdges::Overwrite &) {}, [](const FlowEdges::Fill &) {},
        [](const FlowEdges::Dispatch &) {});
}

// What the terms give a value of `origin`, each source's claim asked of
// `claimOf`: the least of what each term allows, from everything where the
// op makes the value or moves into it, and nothing where no edge explains
// it. None where a term is a memo label's, which the marking alone
// follows: the rule says nothing of such a value.
template <class Source, std::invocable<const Source &> ClaimOf>
std::optional<Unique> claimFrom(Origin origin, llvm::ArrayRef<Term<Source>> terms,
                                ClaimOf &&claimOf) {
  Unique claim = origin == Origin::Unexplained ? Unique::None : Unique::Deep;
  for (const Term<Source> &term : terms) {
    switch (term.via) {
    // Essential, the two values a whole moves into: one the op makes new,
    // whose own cells are new and which holds beyond them what the source
    // claims (a reindex that builds), as a part outside its own cells; any
    // other is the source itself at another type, claiming what it does.
    case Via::Moved:
      claim = lesser(claim, origin == Origin::Fresh
                                ? freshest(FieldReach::Other, claimOf(term.from))
                                : claimOf(term.from));
      break;
    case Via::Copied:
      claim = Unique::None;
      break;
    case Via::ReadOut:
      claim = lesser(claim, readClaim(term.reach, term.uses, claimOf(term.from)));
      break;
    case Via::Built:
      claim = lesser(claim, freshest(term.reach, claimOf(term.from)));
      break;
    case Via::Filled:
      claim = lesser(claim, freshest(term.reach, term.held));
      break;
    case Via::Slot:
      claim = lesser(claim, term.held);
      break;
    case Via::Anchored:
      return std::nullopt;
    }
  }
  return claim;
}

// The origin a value's terms give it: made new by the op, or moved into
// whole, or neither.
template <class Source>
Origin originOf(Made made, llvm::ArrayRef<Term<Source>> terms) {
  // A part built or filled says what the value may claim, never that
  // anything moved into it whole.
  if (made == Made::New)
    return Origin::Fresh;
  bool whole = llvm::any_of(terms, [](const Term<Source> &term) {
    return term.via != Via::Built && term.via != Via::Filled;
  });
  return whole ? Origin::Flows : Origin::Unexplained;
}

// What `value` claims as a source of the rule, read off its type: its
// hold's claim, and everything for a value with no hold, which holds no
// reference (a word, a cell before its init): nothing it reaches is shared.
inline Unique claimOfSource(mlir::Value value) {
  std::optional<Hold> hold = holdOf(value.getType());
  return hold ? hold->claim() : Unique::Deep;
}

// How a use hands on the value it uses, as its op says: as the value again
// or a part read of it (a position that keeps its operand's value, a region
// entry or rejoin that forwards it, a field or view read out of it), each
// such value handed to `onValue` with whether it lives in a region that runs
// again; lent to a parameter of a function by name, handed to `onLend`,
// whose callee answers for what it keeps; or kept (moved or copied whole
// into a value, built into one, returned, given up, or used by an op that
// says nothing of where it goes).
enum class Runs : std::uint8_t { Once, Again };
enum class Passage : std::uint8_t { HandsOn, Lends, Keeps };
template <std::invocable<mlir::Value, Runs> OnValue,
          std::invocable<const FlowSource::Parameter &> OnLend>
Passage passageOf(mlir::OpOperand &use, OnValue &&onValue, OnLend &&onLend) {
  mlir::Operation *owner = use.getOwner();
  if (owner->hasTrait<SameValue>()) {
    for (mlir::Value result : owner->getResults())
      onValue(result, Runs::Once);
    return Passage::HandsOn;
  }
  Passage passage = Passage::Keeps;
  forwardedValues(owner, [&](mlir::OpOperand &operand, mlir::Value input) {
    if (&operand != &use)
      return;
    auto arg = llvm::dyn_cast<mlir::BlockArgument>(input);
    onValue(input, arg && repeats(arg.getOwner()->getParentOp()) ? Runs::Again : Runs::Once);
    passage = Passage::HandsOn;
  });
  if (passage == Passage::HandsOn)
    return passage;
  auto declared = llvm::dyn_cast<FlowOpInterface>(owner);
  if (!declared)
    return Passage::Keeps;
  FlowEdges edges;
  declared.getFlowEdges(edges);
  passage = Passage::HandsOn;
  auto worst = [&](Passage each) {
    if (static_cast<unsigned>(each) > static_cast<unsigned>(passage))
      passage = each;
  };
  for (const FlowEdges::Edge &edge : edges.edges()) {
    if (!edge.carries(Carrier::Reference))
      continue;
    match(
        edge.move,
        [&](const FlowEdges::Flow &flow) {
          bool from = match(
              flow.from.at, [&](const FlowSource::Taken &taken) { return taken.use == &use; },
              [&](const FlowSource::Whole &whole) { return whole.value == use.get(); },
              [&](const FlowSource::Part &) { return *flow.from.value() == use.get(); },
              [](const OneOf<FlowSource::Parameter, FlowSource::Result> auto &) { return false; });
          if (!from)
            return;
          match(
              flow.to.at,
              [&](const FlowSource::Parameter &parameter) {
                onLend(parameter);
                worst(Passage::Lends);
              },
              [&](const FlowSource::Whole &into) {
                bool read = match(
                    flow.from.at,
                    [](const FlowSource::Part &part) { return reachOf(part) == Reach::Read; },
                    [](const OneOf<FlowSource::Taken, FlowSource::Whole, FlowSource::Parameter,
                                   FlowSource::Result> auto &) { return false; });
                if (read)
                  onValue(into.value, Runs::Once);
                else
                  worst(Passage::Keeps);
              },
              [&](const OneOf<FlowPlace::Part, FlowSource::Result> auto &) {
                worst(Passage::Keeps);
              });
        },
        [&](const FlowEdges::Release &release) {
          if (release.use == &use)
            worst(Passage::Keeps);
        },
        [](const OneOf<FlowEdges::Unify, FlowEdges::Source, FlowEdges::Fresh,
                       FlowEdges::Overwrite, FlowEdges::Fill, FlowEdges::Dispatch,
                       FlowEdges::Constant> auto &) {});
  }
  return passage;
}

// Whether a callee keeps what a parameter of it is lent past the call, as
// the program's marking of what each callee keeps says.
enum class Lent : std::uint8_t { Ends, Kept };

// The value `value` is outside the regions it was entered into: where it is
// an argument of a region its op runs at most once each time it is entered,
// entered from one place (a match's scrutinee or a value forwarded beside it
// into a case, a jump's argument into the one join region it enters), the
// value entered there, refined, its cell the same, climbed in turn; else
// `value` itself. An argument entered from several places (a join region
// two jumps reach) may be any of their values, so it is no one cell.
mlir::Value enteredFrom(mlir::Value value);

// A value used many times entering a position that uses it once by a cast
// (idr.lin.cast into a linear position) is that position's alone where
// every other use of what holds its cell, the value it was entered from
// (enteredFrom) and what that is handed on as, the cast's operand among
// them, is a read that ends before the cast: it runs in a region the cast's
// excludes, or it runs before the cast (an op that encloses the cast hands
// its operands into the regions it enters before it) and hands the value
// on (passageOf) to uses that are such reads in turn, in no region that
// runs again, or lends it to a callee that keeps nothing of it (`keeps`);
// and the cast does not run again on the one value. Before references are
// counted the cast's `once` result then carries what that value's cell
// holds (carriedClaim), the values themselves still claiming nothing. The
// in-place promise, the verifier's local rule and idr-unique-results all
// ask this, one rule: the promise with the program's marking of what each
// callee keeps; the verifier, which no such fact of the IR reaches yet,
// with every lend ending at its call, so it checks the local half alone
// (where the callee half lives is open); idr-unique-results, which derives
// claims and reads no such fact either, with every lend outliving its call.
struct EntersAlone {
  // The value whose cell the cast's result carries (enteredFrom).
  mlir::Value value;
};
// Another use that may still hold the value where the cast enters it.
struct HeldElsewhere {
  mlir::OpOperand *by;
};
using Entry = std::variant<EntersAlone, HeldElsewhere>;

template <std::invocable<const FlowSource::Parameter &> Keeps>
  requires std::same_as<std::invoke_result_t<Keeps &, const FlowSource::Parameter &>, Lent>
Entry entryOf(LinCastOp enter, Keeps &&keeps) {
  mlir::Operation *cast = enter.getOperation();
  mlir::Value held = enteredFrom(enter.getValue());
  if (runsAgainOn(cast, held))
    return HeldElsewhere{&cast->getOpOperand(0)};
  // Each use still to read: the held value's own, and those of what a use
  // hands it on as, down to the cast's operand. An explicit stack, so a
  // long chain costs no native frames; it follows no region that runs
  // again, so it reads each use once on each path to it.
  llvm::SmallVector<mlir::OpOperand *> work;
  auto push = [&](mlir::Value of) {
    for (mlir::OpOperand &use : of.getUses())
      if (use.getOwner() != cast)
        work.push_back(&use);
  };
  push(held);
  while (!work.empty()) {
    mlir::OpOperand *use = work.pop_back_val();
    mlir::Operation *owner = use->getOwner();
    if (mlir::insideMutuallyExclusiveRegions(owner, cast))
      continue;
    if (!owner->isProperAncestor(cast) && runsAfter(owner, cast))
      return HeldElsewhere{use};
    enum class Holds : std::uint8_t { Ends, Past } holds = Holds::Ends;
    Passage passage = passageOf(
        *use,
        [&](mlir::Value on, Runs runs) {
          if (runs == Runs::Again)
            holds = Holds::Past;
          else
            push(on);
        },
        [&](const FlowSource::Parameter &parameter) {
          if (keeps(parameter) == Lent::Kept)
            holds = Holds::Past;
        });
    if (passage == Passage::Keeps || holds == Holds::Past)
      return HeldElsewhere{use};
  }
  return EntersAlone{held};
}

// What explains the cell of a value used many times that a cast enters
// (EntersAlone's): the same value at another grade (a position that keeps
// its operand's value), whose own type says what it holds; a value its op
// makes new, which holds what its parts allow; or nothing here (a
// parameter, a value forwarded into a region from several places or one
// that runs again, a call's result), so it carries nothing.
struct SameCell {
  mlir::Value of;
};
struct NewCell {
  mlir::Operation *op;
};
struct UnknownCell {};
using CellOf = std::variant<SameCell, NewCell, UnknownCell>;
CellOf cellOf(mlir::Value value);

// Each term of `value` that `cell`'s op, which makes it new, gives it by
// its declared edges, handed to `each`: what the cell holds is what they
// allow a fresh value.
template <std::invocable<const Term<mlir::Value> &> Each>
void forEachTermOf(const NewCell &cell, mlir::Value value, Each &&each) {
  FlowEdges edges;
  llvm::cast<FlowOpInterface>(cell.op).getFlowEdges(edges);
  forEachTerm(
      edges,
      [&](mlir::Value target, const Term<mlir::Value> &term) {
        if (target == value)
          each(term);
      },
      [](mlir::Value) {});
}

// What a value used many times holds where a cast enters it as its one
// use (EntersAlone's): the claim its cell's source gives it, read off the
// source types.
Unique carriedClaim(mlir::Value value);

// The rule in the verifier's walk of a function, after every pass: every
// value that claims anything of its sharing, and that an op declares how it
// makes, claims no more than the rule gives it from its sources' types (a
// fresh value from what its parts claim, a value moved on from what it was
// moved from claims, a cast that enters a value used many times as its one
// use from what the value claims and what the cell of the value it was
// entered from holds (entryOf), a part read or taken out from the value's
// claim), every value forwarded into one claims at least
// what that one does, and none is copied, read whole into another value by an
// op that neither takes nor gives it up. A call's results are its callee's
// signature's, a result its op infers is held to the inference by the op's
// verifier, and a result its op holds to its operand's value at a grade that
// only forgets (a share, whose edges give the operand up), so none is judged
// here unless the op admits it at a claim beyond what it infers; a value
// taken out of a memo label's field is the marking's. A failure is the error
// of the pass that broke it.
class LocalCheck {
public:
  mlir::LogicalResult enter(mlir::Operation *, mlir::Region &) { return mlir::success(); }
  mlir::LogicalResult check(mlir::Operation *op);
  void leave() {}
};

static_assert(families::FunctionRule<LocalCheck>);

} // namespace idr::ownership

#endif // IDR_ANALYSIS_OWNERSHIP_LOCAL_H
