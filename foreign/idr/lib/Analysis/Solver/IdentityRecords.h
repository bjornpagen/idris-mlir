// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The records the gives-back solve reads (Identities.h): how one function
// builds each of its values, as far as giving back reads it, numbered in
// walk order. Private to IdentitiesRecord.cpp, which writes them,
// IdentitiesRebuilds.cpp, which reads one under assumptions, and
// Identities.cpp, the fixpoint over a component's.
#ifndef IDR_LIB_ANALYSIS_SOLVER_IDENTITYRECORDS_H
#define IDR_LIB_ANALYSIS_SOLVER_IDENTITYRECORDS_H

#include "idr/Analysis/Identities.h"
#include "idr/Analysis/Solver/Extraction.h"
#include "idr/Support/Id.h"

#include "mlir/IR/Attributes.h"
#include "mlir/IR/Types.h"

#include <cstdint>
#include <optional>
#include <span>
#include <variant>
#include <vector>

namespace idr::identities {

struct ValueTag {
  using Minter = solver::Numbering<ValueTag>;
};
// A value of one record, by its place in the function's walk: every value
// it is made from has a smaller id.
using ValueId = Id<ValueTag>;

// One step down into a value, inside the solve: a field of a constructor,
// or the predecessor of a natural (the field of its successor, as Idris
// shapes a natural). What the solve publishes keeps only the steps a
// given_back path can hold.
struct Field {
  Tag tag;
  std::uint32_t index;
  friend bool operator==(const Field &, const Field &) = default;
};
struct Predecessor {
  friend bool operator==(Predecessor, Predecessor) = default;
};
using Step = std::variant<Field, Predecessor>;

// A run of one of a record's flat arrays.
struct Range {
  std::uint32_t first = 0, count = 0;
};

// What a value is known to be where it is used, read off the case regions
// around the use: built by the constructor of a tag (a data match's case,
// or its default where one constructor is left), or a literal (a literal
// match's case). A constant says the same of itself: a constructor with no
// fields is its tag, any other constant its literal. Two literals are one
// when they are one value, whatever width a big was written at.
struct KnownTag {
  Tag tag;
  friend bool operator==(const KnownTag &, const KnownTag &) = default;
};
struct KnownLiteral {
  mlir::Attribute literal;
  friend bool operator==(const KnownLiteral &a, const KnownLiteral &b);
};
using Known = std::variant<KnownTag, KnownLiteral>;

// How a value is built, as far as giving back reads it. A value this
// question does not look into is opaque: an op's own result it cannot see
// through, a memo cell's part (a memo cell is written when it is forced,
// so no part of it is a part of anything), a region's argument.
namespace build {
struct Opaque {};
// The function's argument.
struct Entry {
  std::uint32_t argument;
};
// Another value itself: an op that keeps its operand's value, or what a
// case binds of its scrutinee (idr::sourceOf).
struct Same {
  ValueId of;
};
// A field of a value refined to its constructor, of type `type`.
struct Read {
  ValueId of;
  Field field;
  mlir::Type type;
};
// The predecessor of a natural.
struct Pred {
  ValueId of;
};
// Result `result` of call site `call`, of type `type`: the one place an
// assumption is read.
struct Result {
  std::uint32_t call;
  std::uint32_t result;
  mlir::Type type;
};
// A constructor, its fields a run of the record's operands, with the
// constructor facts of the matches around it.
struct Con {
  Tag tag;
  mlir::Type type;
  Range fields;
  Range frames;
};
// `of` plus one.
struct Successor {
  ValueId of;
};
// Result `result` of the match whose regions are `side`.
struct Join {
  std::uint32_t side;
  std::uint32_t result;
};
// A constant of type `type`: what a case around its use must say of a
// part for the constant to be that part.
struct Constant {
  Known known;
  mlir::Type type;
};
} // namespace build
using Build = std::variant<build::Opaque, build::Entry, build::Same, build::Read, build::Pred,
                           build::Result, build::Con, build::Successor, build::Join,
                           build::Constant>;

// A call of another function: its callee and its arguments, a run of the
// record's operands.
struct CallSite {
  solver::FunctionId callee;
  Range args;
};

// What a case region around a use says its scrutinee is.
struct Frame {
  ValueId scrutinee;
  Known known;
};

// One region of a match: one that never returns (it ends in a crash), or
// one that yields, its values a run of the operands, with its frames.
struct NeverReturns {};
struct Yields {
  Range values;
  Range frames;
};
using Arm = std::variant<NeverReturns, Yields>;

struct Return {
  Range values;
  Range frames;
};

// One function, read once.
struct Record {
  solver::FunctionId id;
  Count<ValueId> values;
  IndexVector<ValueId, Build> builds;
  std::vector<ValueId> operands;
  std::vector<Frame> frames;
  std::vector<CallSite> calls;
  // Each match's arms: `sides[s]` is a run of `arms`.
  std::vector<Range> sides;
  std::vector<Arm> arms;
  std::vector<Return> returns;
  // Every argument's and result's type, with its grade stripped.
  std::vector<mlir::Type> argumentTypes;
  std::vector<mlir::Type> resultTypes;

  std::span<const ValueId> run(Range range) const {
    return std::span<const ValueId>(operands).subspan(range.first, range.count);
  }
  std::span<const Frame> framesOf(Range range) const {
    return std::span<const Frame>(frames).subspan(range.first, range.count);
  }
};

template <solver::FunctionNames N>
Record readRecord(const N &names, const solver::Member &member);

// What a record's function gives back, given what each of its call sites'
// callees give back (`callees[c]` for call site c): the subset of `asked`,
// each a whole result given back as a whole argument, that every return
// rebuilds (IdentitiesRebuilds.cpp).
Facts wholeFactsAmong(const Record &record, std::span<const std::span<const GivesBack>> callees,
                      std::span<const GivesBack> asked);

// Every fact a record's function gives back, per result field path, under
// the same callees' facts: what a member publishes once its component's
// fixpoint holds.
Facts everyFact(const Record &record, std::span<const std::span<const GivesBack>> callees);

// Whether a value of `a` and one of `b` are one value at run time, so one
// may be given back as the other: the same type once grades are stripped,
// or one family application an instance of the other's levels.
enum class Represents : std::uint8_t { Differently, Alike };
Represents representation(mlir::Type a, mlir::Type b);

struct Component::Records {
  std::vector<Record> members;
  // The distinct callees outside the component, in the order first met.
  std::vector<solver::FunctionId> outside;
  // Each member's call sites, each a member's position or an outside
  // callee's index.
  struct InComponent {
    std::uint32_t member;
  };
  struct Elsewhere {
    std::uint32_t outside;
  };
  using Callee = std::variant<InComponent, Elsewhere>;
  std::vector<std::vector<Callee>> callees;
};

} // namespace idr::identities

#endif // IDR_LIB_ANALYSIS_SOLVER_IDENTITYRECORDS_H
