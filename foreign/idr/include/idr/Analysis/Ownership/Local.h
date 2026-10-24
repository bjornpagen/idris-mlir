// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The local rule of exclusivity: what QTT and freshness prove of a value's
// sharing from its definition alone. A value is unique where it is fresh
// (a constructor's, a recycled cell's, or a call's result whose signature
// says so) or taken or read at a linear position from one that is, and it
// flows only through linear positions. Each op states its part in the edges
// it declares (FlowEdges.h), so the rule names no op: a fresh value claims
// the most whose read of each part moved into it gives no more than the
// part gives, which is nothing where the part is used many times; a value
// moved on claims what was moved; a part read or taken
// out claims what the grade's read of it gives (Hold::read), except a
// capture moved out of a memo label's field, which holds what the label's
// field held; a copy, a constant and a value no edge explains claim
// nothing.
//
// Two readers instantiate it. The verifier holds every value typed `unique
// deep` to it, one op at a time, each source's claim its type's (LocalCheck,
// a rule of the function's one walk). idr-unique-results solves it over each
// body before bufferization, each call's result its callee's derived
// claim, and writes what it proves into the types; the exclusivity marking
// after bufferization covers only what this rule cannot prove.
#ifndef IDR_ANALYSIS_OWNERSHIP_LOCAL_H
#define IDR_ANALYSIS_OWNERSHIP_LOCAL_H

#include "idr/Analysis/Ownership/Facts.h"
#include "idr/IR/Families/Scope.h"
#include "idr/IR/Flow.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Match.h"

// Whether the program's references are counted (StageCounting).
#include "idr/IR/Generated/StageFacts.h.inc"

#include "mlir/IR/Operation.h"
#include "mlir/IR/Region.h"
#include "mlir/IR/Value.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/STLExtras.h"

#include <algorithm>
#include <concepts>
#include <cstdint>
#include <optional>
#include <utility>

namespace idr::ownership {

// The claims in their order: nothing, the own cells, everything reached.
constexpr bool covers(Unique held, Unique asked) {
  return static_cast<unsigned>(held) >= static_cast<unsigned>(asked);
}
constexpr Unique lesser(Unique a, Unique b) { return covers(a, b) ? b : a; }
constexpr Unique greater(Unique a, Unique b) { return covers(a, b) ? a : b; }

// What a part gives a value built of it, used `uses` times and claiming
// `held`: at one use its one reference moves into the value with all it
// claims; at many uses its cells are reached by its other uses as well, so
// it gives no claim. Read from the specification's table of it
// (givenClaims).
constexpr Unique givenClaim(Uses uses, Unique held) {
  return givenClaims[static_cast<unsigned>(uses)][static_cast<unsigned>(held)];
}

// The most a fresh value may claim, built of a part reached as `reach`,
// used `uses` times and claiming `held`: the greatest claim whose read of
// the part at one use, the read that gives most, gives no more than the
// part gives (givenClaim). A part outside the value's own cells bounds only
// a deep claim. Read from the specification's tables of both
// (freshestClaims), by whose rule, its freshClaim, the frontend writes a
// constructor's claim too.
constexpr Unique freshest(FieldReach reach, Uses uses, Unique held) {
  return freshestClaims[static_cast<unsigned>(reach)]
                       [static_cast<unsigned>(givenClaim(uses, held))];
}

// How a value is given what its source holds, as an edge into it says.
enum class Via : std::uint8_t {
  // The source's use taken over whole, or forwarded: what the source claims.
  Moved,
  // Read and not given up, or a constant: shared with whatever else holds it.
  Copied,
  // A part read or taken out of the source: what the source's claim reads
  // there.
  ReadOut,
  // Moved into a part of the value the op builds: the value may claim
  // what that part bounds at its uses, nothing where it is used many times.
  Built,
  // A part of the value the op builds filled by what the op does not take
  // over: a value read, shared; or a hole another op writes, holding what
  // its destination's type bounds the write to (`held`).
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
// reaches, any other nothing) or the part built in is used (the value moved
// in, or what a hole's type states: one used many times gives nothing),
// and, for a slot or a part a hole fills, what the slot's type claims.
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
                    [&](const FlowSource::Taken &taken) {
                      mlir::Value moved = taken.use->get();
                      term(built, Term<mlir::Value>{moved, Via::Built, reach,
                                                    usesOf(moved.getType())});
                    },
                    [&](const NotTaken auto &) {
                      term(built, Term<mlir::Value>{mlir::Value(), Via::Filled, reach});
                    });
              },
              [](const FlowSource::Parameter &) {}, [](const FlowSource::Result &) {});
        },
        // A part of a value the op builds that it joins to another place,
        // a hole another op writes: what fills it is what the hole's
        // destination's type bounds, at the uses it states, and anything
        // where the place is no hole.
        [&](const FlowEdges::Unify &unify) {
          auto fills = [](const FlowPlace &place) -> std::pair<Uses, Unique> {
            return match(
                place.at,
                [](const FlowPlace::Part &part) {
                  return match(
                      part.anchor.place,
                      [](const FlowAnchor::Hole &hole) {
                        mlir::Type slot = hole.dest.getValue();
                        return std::pair(usesOf(slot), claimOf(slot));
                      },
                      [](const OneOf<FlowAnchor::Field, FlowAnchor::Elements, FlowAnchor::Forced,
                                     FlowAnchor::MemoState, FlowAnchor::Capture> auto &) {
                        return std::pair(Uses::Once, Unique::None);
                      });
                },
                [](const WholePlace auto &) { return std::pair(Uses::Once, Unique::None); });
          };
          auto filled = [&](const FlowPlace &place, const FlowPlace &other) {
            match(
                place.at,
                [&](const FlowPlace::Part &part) {
                  auto [uses, held] = fills(other);
                  term(part.of, Term<mlir::Value>{mlir::Value(), Via::Filled, reachAt(part.anchor),
                                                  uses, held});
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
    case Via::Moved:
      claim = lesser(claim, claimOf(term.from));
      break;
    case Via::Copied:
      claim = Unique::None;
      break;
    case Via::ReadOut:
      claim = lesser(claim, readClaim(term.reach, term.uses, claimOf(term.from)));
      break;
    case Via::Built:
      claim = lesser(claim, freshest(term.reach, term.uses, claimOf(term.from)));
      break;
    case Via::Filled:
      claim = lesser(claim, freshest(term.reach, term.uses, term.held));
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

// Whether `value` flows only through linear positions: Idris proved it used
// once (its grade's uses, which the linearity rule holds every pass to), or
// it has one use.
inline bool flowsLinearly(mlir::Value value) {
  return usesOf(value.getType()) == Uses::Once || value.hasOneUse();
}

// The rule in the verifier's walk of a function, after every pass: every
// value typed `unique deep` that an op declares how it makes is what the
// rule gives it from its sources' types (a fresh value whose parts are, a
// value moved on, a part read or taken out of a `unique deep` value), every
// value forwarded into one typed so is, and none is copied, read whole into
// another value by an op that neither takes nor gives it up. A call's
// results are its callee's signature's, and a result its op infers is held
// to the inference by the op's verifier, so neither is judged here unless
// the op admits it at a claim beyond what it infers; a value taken out of a
// memo label's field is the marking's. A failure is the error of the pass
// that broke it.
//
// Essential, two stages: before references are counted, a value's grade
// says how many references counting will make of it, so a part used many
// times gives what is built of it nothing; once they are counted, each is
// explicit (a value taken over before its last use is taken as a dup, which
// claims nothing, and its owner is shared where it is made), so a part built
// in is the one reference it is and gives all its type claims, as
// exclusivity writes them, proved on the references placement made.
class LocalCheck {
public:
  explicit LocalCheck(StageCounting counting) : counting(counting) {}
  mlir::LogicalResult enter(mlir::Operation *, mlir::Region &) { return mlir::success(); }
  mlir::LogicalResult check(mlir::Operation *op);
  void leave() {}

private:
  StageCounting counting;
};

static_assert(families::FunctionRule<LocalCheck>);

} // namespace idr::ownership

#endif // IDR_ANALYSIS_OWNERSHIP_LOCAL_H
