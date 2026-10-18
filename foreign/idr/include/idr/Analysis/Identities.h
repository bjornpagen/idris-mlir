// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The functions of one component of the direct calls that give back one of
// their arguments, found together: what idr-identity makes every call of
// them.
//
// Every function of the component starts out assumed to give back each
// argument that could be its result: of the result's type at any quantity.
// A function that does not, under what is assumed of the rest, loses the
// assumption, and the functions that call it are checked again. Each check
// can only drop an assumption, each drop is queued once, and there are
// finitely many, so the work ends; what is left is the greatest fixpoint,
// so the functions of a mutual recursion are found together, and whatever
// order the functions are checked in finds the same ones. A callee outside
// the component is final, and what it gives back is read frozen. Each
// function is walked once before that fixpoint, into a record of how its
// body is built; what remains of the assumptions is read off that record,
// so the arguments share one walk and a requeued caller is not walked
// again.
//
// A function of a program in the owned stage gives back nothing, since a
// counted value there cannot stand for a fresh one; nor does one that takes
// a world, whose call is where its effects are ordered.
#ifndef IDR_ANALYSIS_IDENTITIES_H
#define IDR_ANALYSIS_IDENTITIES_H

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <optional>
#include <variant>
#include <vector>

namespace idr::identities {

// What the solve reads of a callee that is not in the component it solves:
// the argument it gives back, frozen, if it gives one back. Whether a call
// returns, and what else it does, is the call's own property (its
// effects), whoever its callee is.
using Outside = llvm::function_ref<std::optional<unsigned>(mlir::StringAttr callee)>;

// The argument each function of `component` gives back, if it gives one
// back, in the order of `component`. `outside` answers for a callee that is
// not in `component`; a call that only computes, as its effects say, needs
// no assumption.
llvm::SmallVector<std::optional<unsigned>> givesBackOf(llvm::ArrayRef<FuncOp> component,
                                                       Outside outside);

// The functions of the component, by name.
using Members = llvm::DenseMap<mlir::StringAttr, FuncOp>;

// The parameters of each function, by name, assumed to be given back.
using Assumed = llvm::DenseMap<mlir::StringAttr, llvm::SmallVector<unsigned, 1>>;

// The arguments `fn` could give back.
llvm::SmallVector<unsigned, 1> candidates(FuncOp fn);

// One walk of a function, for every argument it might give back
// (IdentitiesRecord.cpp), and what it gives back under a set of
// assumptions, read off the walk (IdentitiesRebuilds.cpp). A record is
// never written once walked.
class Record {
public:
  // The walk of `fn` for `candidates`. Nothing when no argument can be
  // given back under any assumption: a terminator this question cannot
  // keep, or an op that does not only compute.
  static std::optional<Record> walk(FuncOp fn, llvm::ArrayRef<unsigned> candidates);

  // The subset of `asked`, in that order, that the walk gives back under
  // `assumed`; each of `asked` is one of the walk's candidates.
  llvm::SmallVector<unsigned, 1> givesBack(llvm::ArrayRef<unsigned> asked,
                                           const Assumed &assumed) const;

private:
  class Walker;
  class Reading;

  // A value of the walk, by its number.
  enum class Id : unsigned {};

  // How a value is built, as far as giving back reads it. A value this
  // question does not look into, a memo cell's part among them, is opaque:
  // a memo cell is written when it is forced, so no part of it is a part
  // of anything.
  struct Opaque {};
  // The function's argument.
  struct Entry {
    unsigned arg;
  };
  // Another value itself: the result of an op that keeps its operand's
  // value, or the argument of a match's default region, which is the
  // scrutinee (idr::sourceOf).
  struct Same {
    Id of;
  };
  // A field of a value: read by idr.field, or bound by a case.
  struct Field {
    Id of;
    Tag tag;
    unsigned index;
    mlir::Type type;
  };
  // The predecessor of a natural.
  struct Pred {
    Id of;
  };
  // A call: the one place an assumption is read.
  struct Call {
    mlir::StringAttr callee;
    // It returns: its effects, which contain its callee's, hold no
    // divergence, so it reaches nothing Idris did not prove total.
    bool returns;
    llvm::SmallVector<Id, 4> args;
  };
  struct Con {
    Tag tag;
    mlir::Type type;
    llvm::SmallVector<Id, 4> fields;
    llvm::SmallVector<mlir::Type, 4> types;
  };
  // `of` plus one.
  struct Successor {
    Id of;
  };
  // A result of a match.
  struct Join {
    unsigned side;
    unsigned result;
  };
  struct Constant {
    mlir::Attribute value;
    mlir::Type type;
    // The tag of a constructor with no fields: the one value it has.
    std::optional<Tag> fieldless;
  };
  using Build =
      std::variant<Opaque, Entry, Same, Field, Pred, Call, Con, Successor, Join, Constant>;

  // What a match says its scrutinee is in one of its regions: built by the
  // constructor of a tag, or a literal.
  struct KnownTag {
    Tag tag;
  };
  struct KnownLiteral {
    mlir::Attribute literal;
  };
  using Fact = std::variant<KnownTag, KnownLiteral>;
  // A match a use sits in, inner first, where its region says something.
  struct Frame {
    Id scrutinee;
    Fact fact;
  };
  using Frames = llvm::SmallVector<Frame, 2>;

  // One region of a match that runs, which ends in ub.unreachable (never
  // taken) or in a yield, which must rebuild: the match's verifier admits
  // no other end. An empty default region, of an exhaustive match, never
  // runs and is no arm.
  struct Unreachable {};
  struct Yields {
    llvm::SmallVector<Id, 1> values;
    Frames frames;
  };
  using Arm = std::variant<Unreachable, Yields>;

  struct Ret {
    Id value;
    Frames frames;
  };

  Record() = default;

  const Build &build(Id id) const { return nodes[static_cast<unsigned>(id)]; }

  // The candidates, by slot, the slot of each, and each one's type at no
  // grade.
  llvm::SmallVector<unsigned, 1> arguments;
  llvm::DenseMap<unsigned, unsigned> slots;
  llvm::SmallVector<mlir::Type, 1> types;
  std::vector<Build> nodes;
  llvm::SmallVector<llvm::SmallVector<Arm, 2>, 1> joins;
  // The calls that do not only compute: each must be a call assumed to
  // give back what it is passed, that it may rely on.
  llvm::SmallVector<Id, 2> reliant;
  llvm::SmallVector<Ret, 1> rets;
};

} // namespace idr::identities

#endif // IDR_ANALYSIS_IDENTITIES_H
