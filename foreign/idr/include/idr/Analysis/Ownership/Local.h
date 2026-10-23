// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The local rule of exclusivity: what QTT and freshness prove of a value's
// sharing from its definition alone. A value is unique where it is fresh
// (a constructor's, a recycled cell's, or a call's result whose signature
// says so) or taken or read at a linear position from one that is, and it
// flows only through linear positions. Each op states its part in the edges
// it declares (FlowEdges.h), so the rule names no op: a fresh value claims
// the most whose read of each part moved into it gives no more than the
// part claims; a value moved on claims what was moved; a part read or taken
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

#include "mlir/IR/Operation.h"
#include "mlir/IR/Region.h"
#include "mlir/IR/Value.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/STLExtras.h"

#include <algorithm>
#include <concepts>
#include <cstdint>
#include <optional>

namespace idr::ownership {

// The claims in their order: nothing, the own cells, everything reached.
constexpr bool covers(Unique held, Unique asked) {
  return static_cast<unsigned>(held) >= static_cast<unsigned>(asked);
}
constexpr Unique lesser(Unique a, Unique b) { return covers(a, b) ? b : a; }
constexpr Unique greater(Unique a, Unique b) { return covers(a, b) ? a : b; }

// The most a fresh value may claim, built of a part reached as `reach` that
// claims `given`: the greatest claim whose read of the part at one use, the
// read that gives most (the grade's table), gives no more than the part
// holds. A part outside the value's own cells bounds only a deep claim.
constexpr Unique freshest(FieldReach reach, Unique given) {
  if (covers(given, readClaim(reach, Uses::Once, Unique::Deep)))
    return Unique::Deep;
  if (covers(given, readClaim(reach, Uses::Once, Unique::Self)))
    return Unique::Self;
  return Unique::None;
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
  // what that part bounds.
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
// reaches, any other nothing), and, for a slot or a part a hole fills, what
// the slot's type claims.
template <class Source>
struct Term {
  Source from;
  Via via;
  FieldReach reach;
  Uses uses = Uses::Once;
  Unique held = Unique::None;
};

// What the place a part is read from holds once the op has read it, as the
// op's edges say: nothing, the reference it held moved out with the part,
// where the op takes over the whole the part is of, or keeps the whole and
// declares the place overwritten (an array's take, a memo cell's exchange:
// the place holds nothing until a later write fills it); or the reference
// it held, which the part only views.
enum class PlaceAfter : std::uint8_t { Emptied, Kept };

// The place `part` is read from among `edges`, the edges of the op that
// reads it.
inline PlaceAfter placeAfter(const FlowEdges &edges, const FlowSource::Part &part) {
  if (reachOf(part) == Reach::Taken)
    return PlaceAfter::Emptied;
  mlir::Value whole = part.value();
  bool overwritten = llvm::any_of(edges.edges(), [&](const FlowEdges::Edge &edge) {
    return match(
        edge.move,
        [&](const FlowEdges::Overwrite &over) {
          return over.place.of == whole && over.place.anchor == part.anchor;
        },
        [](const OneOf<FlowEdges::Flow, FlowEdges::Unify, FlowEdges::Source, FlowEdges::Fresh,
                       FlowEdges::Release, FlowEdges::Fill, FlowEdges::Constant,
                       FlowEdges::Dispatch> auto &) { return false; });
  });
  return overwritten ? PlaceAfter::Emptied : PlaceAfter::Kept;
}

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
class LocalCheck {
public:
  mlir::LogicalResult enter(mlir::Operation *, mlir::Region &) { return mlir::success(); }
  mlir::LogicalResult check(mlir::Operation *op);
  void leave() {}
};

static_assert(families::FunctionRule<LocalCheck>);

} // namespace idr::ownership

#endif // IDR_ANALYSIS_OWNERSHIP_LOCAL_H
