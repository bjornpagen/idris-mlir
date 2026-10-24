// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The grade, `!idr.graded<uses, hold, T>`: what Idris proved of a value,
// kept in its type where no pass can drop it, and what counting and the
// lifetimes learn of it. Its uses are on every type; its hold only on a
// type that holds references. A hold has two axes, never one enum: who
// frees what the value holds (its count, the end of its lifetime, or
// nothing for static data), and what is known of its sharing (nothing, its
// own cells, everything it reaches). Every pair is a hold but a
// claim on static data, which is shared by definition and has no
// constructor. A lifetime is not part of the grade: it is an SSA value, which
// the op that makes a value names (Lifetimes.h).
//
// The axes, their spellings and the tables of their algebra are generated
// from the dialect's Idris specification (Spec.Grades.Grade), where the laws
// are proved; the C++ reads the tables, never a second proof. Declared over
// mlir::Type and mlir::Value, before the dialect's generated types: the
// generated type builders and constraints name them.
#ifndef IDR_IR_GRADES_H
#define IDR_IR_GRADES_H

#include "mlir/IR/Builders.h"
#include "mlir/IR/OpImplementation.h"
#include "mlir/IR/Types.h"
#include "mlir/IR/Value.h"
#include "mlir/Support/WalkResult.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/Hashing.h"
#include "llvm/ADT/SmallVector.h"

#include <concepts>
#include <cstddef>
#include <cstdint>
#include <iterator>
#include <optional>
#include <type_traits>
#include <variant>

// The dialect's ODS enums, `Uses` among them, since the graded type's
// parameter is one; the generated file has no guard of its own, so this
// header is where the dialect includes it. Then the rest of the axes
// (Release, Unique), whether a carrier holds references (Refs, which a
// data type computes when it is made), how far a value's claim reaches
// into a field (FieldReach), a cast's QuantityChange, the seven holds
// (HoldCase) with their facts and what a field read from each gives, and
// the product of uses, printed from Spec.Grades.
#include "idr/IR/IdrEnums.h.inc"
#include "idr/IR/Generated/Grades.h.inc"

namespace idr {

// A constructor's tag, defined with the families (Families/Declaration.h): a
// value's source below names one.
enum class Tag : std::uint32_t;

// Idris's product of uses: a field of a value is used as often as the value
// times the field's own uses.
constexpr Uses times(Uses a, Uses b) {
  return usesTimes[static_cast<unsigned>(a)][static_cast<unsigned>(b)];
}

// Whether `release` frees exactly one hold at each claim, by the
// specification's tables of who frees a hold and what it claims.
consteval bool freesOneHoldPerClaim(Release release) {
  for (Unique unique : allOf<Unique>()) {
    unsigned holds = 0;
    for (HoldCase kase : allOf<HoldCase>())
      if (holdRelease[kase] == release && holdClaim[kase] == unique)
        ++holds;
    if (holds != 1)
      return false;
  }
  return true;
}

// The holds `release` frees, by their claim: the inverse of the
// specification's holdRelease and holdClaim, computed when the compiler is
// built. Asked only of a release that frees one hold at each claim, counted
// and scoped; static data claims nothing.
template <Release release>
inline constexpr EnumArray<Unique, HoldCase> holdsFreedBy = [] {
  static_assert(freesOneHoldPerClaim(release),
                "the release frees one hold at each claim, so its holds invert");
  EnumArray<Unique, HoldCase> holds{};
  for (HoldCase kase : allOf<HoldCase>())
    if (holdRelease[kase] == release)
      holds[holdClaim[kase]] = kase;
  return holds;
}();

// What a value that holds references holds: one of the seven holds of the
// specification (HoldCase), each fact of it a load from the specification's
// table. Built from a case of that set or by its three constructors, and the
// set has no claim on static data, so none can be written.
class Hold {
public:
  // The hold of a case: every case of the set is a hold, so one read back
  // (the graded type's generated codec) is one.
  static constexpr Hold fromCase(HoldCase kase) { return Hold(kase); }
  // Freed by its count, with what is known of its sharing.
  static constexpr Hold counted(Unique unique = Unique::None) {
    return Hold(holdsFreedBy<Release::Counted>[unique]);
  }
  // Freed when the lifetime of the op that made it ends.
  static constexpr Hold scoped(Unique unique = Unique::None) {
    return Hold(holdsFreedBy<Release::Scoped>[unique]);
  }
  // Static data, never freed, shared by definition.
  static constexpr Hold staticData() { return Hold(HoldCase::Static); }

  constexpr HoldCase kase() const { return c; }
  constexpr Release release() const { return holdRelease[c]; }
  // What the hold claims of its sharing: static data claims nothing.
  constexpr Unique claim() const { return holdClaim[c]; }
  // Whether the hold claims at least `unique`.
  constexpr bool claims(Unique unique) const {
    return static_cast<unsigned>(claim()) >= static_cast<unsigned>(unique);
  }
  // Whether a value at this hold may stand where `slot` is asked, with no op
  // between: its claim forgotten down to the slot's, or static data standing
  // for a value of any release that claims nothing.
  constexpr bool fits(Hold slot) const { return (holdFitsMask[c] >> slot.index()) & 1u; }
  // The hold of a field read from a value at this hold, at `uses`, the
  // uses the read gives the field: freed as the value is, claiming what the
  // value's claim reaches into the field (never more than the value), and
  // nothing at many uses, since a value used many times may be duplicated.
  constexpr Hold read(FieldReach reach, Uses uses) const {
    return Hold((uses == Uses::Once ? holdReadsOnce : holdReadsMany)[index()]
                                                                    [static_cast<unsigned>(reach)]);
  }
  // What exclusivity writes once it proves the value's sharing: the claim
  // set where something frees the value; static data has no sharing level
  // and stays as it is.
  constexpr Hold refined(Unique unique) const {
    return release() == Release::Counted  ? counted(unique)
           : release() == Release::Scoped ? scoped(unique)
                                          : *this;
  }
  // The hold as the type prints it.
  llvm::StringRef spelling() const { return holdSpelling[c]; }

  constexpr bool operator==(const Hold &) const = default;
  friend llvm::hash_code hash_value(Hold hold) { return llvm::hash_value(hold.index()); }

private:
  constexpr explicit Hold(HoldCase c) : c(c) {}
  constexpr unsigned index() const { return static_cast<unsigned>(c); }
  HoldCase c;
};

// The strongest hold every one of `holds` fits, by the one order holds fit
// in (Hold::fits): the weakest claim among them, under the release they
// share, or static data among values that claim nothing. None where they
// share none.
inline std::optional<Hold> weakest(llvm::ArrayRef<Hold> holds) {
  std::optional<Hold> best;
  for (HoldCase kase : allOf<HoldCase>()) {
    Hold slot = Hold::fromCase(kase);
    bool fitsAll = true;
    for (Hold hold : holds)
      fitsAll = fitsAll && hold.fits(slot);
    if (fitsAll && (!best || slot.fits(*best)))
      best = slot;
  }
  return best;
}

// A value's grade, as its type says: its uses, and its hold exactly when its
// carrier holds references. The absence is the carrier's fact, not the
// grade's: no hold is ever undecided on a carrier that holds references.
struct Grade {
  Uses uses = Uses::Many;
  std::optional<Hold> hold;
  bool operator==(const Grade &) const = default;
};

// The grade of a type: a graded type's own; a bare type's is its carrier's
// bare grade (many, and counted claiming nothing where it holds
// references); a type used once by its type (a cell, a destination, a
// package) is used once and takes no hold.
Grade gradeOf(mlir::Type type);

// The bare grade of `carrier`, the one a bare type has.
Grade bareGrade(mlir::Type carrier);

// `carrier` at `grade`, in canonical form: never a grade of a graded type;
// the carrier itself at its bare grade, or when it is used once by its type
// (isLinearByType), which takes no grade. The grade must fit its carrier: a
// hold exactly when the carrier holds references (GradedType's verifier).
mlir::Type graded(Grade grade, mlir::Type carrier);

// The type of the value itself, its carrier: T for !idr.graded<…, T>, the
// type otherwise.
mlir::Type unrestricted(mlir::Type type);

// How often a value of `type` may be used, and its hold, if its carrier
// holds references.
Uses usesOf(mlir::Type type);
std::optional<Hold> holdOf(mlir::Type type);

// `type` at other uses, its hold kept; and at another hold, its uses kept.
// A carrier that holds no reference has no hold, and atHold leaves it as it
// is.
mlir::Type atUses(mlir::Type type, Uses uses);
mlir::Type atHold(mlir::Type type, Hold hold);

// Whether a value of `type` is used at most once: by its type, or by its
// grade's uses.
inline bool isLinear(mlir::Type type) { return usesOf(type) == Uses::Once; }

// Whether a value of `type` holds references `release` frees: its count
// (counted), its lifetime (scoped), or nothing (static).
bool freedBy(mlir::Type type, Release release);

// Whether a value of `type` claims at least `unique` of its sharing: its
// own cells unshared (Unique::Self, which a deep claim implies), or
// everything it reaches (Unique::Deep). Counting reads a deep claim off the
// type and tests nothing at run time.
bool claims(mlir::Type type, Unique unique);

// What a value of `type` becomes given on with what its grade claims of its
// sharing forgotten, its release and uses kept (`shared`); and whether a
// value of `from` may stand where `to` is asked with no op between, the
// same carrier at the same uses whose hold fits (`forgets`).
mlir::Type shared(mlir::Type type);
bool forgets(mlir::Type from, mlir::Type to);

// Whether the hold of `from` fits where that of `to` is asked, by the one
// grade order (Hold::fits): the same hold, its claim forgotten, or static
// data standing for a value that claims nothing; never a claim raised, nor
// who frees the value changed. A carrier that holds no reference has no
// hold, and fits. Asked at the same uses by `forgets`, and across uses by
// the linear cast.
bool holdFits(mlir::Type from, mlir::Type to);

// The type at which a value of `given` crosses the edge `edge` makes into a
// place of `asked`: a call's argument into its parameter, a returned value
// into its function's result, a yielded one into its region branch's
// result, a jump's into its join region's parameter. Where the program
// `edge` stands in is at a stage whose edges pass any hold that fits
// (StageEdgeHolds::Fit), and the two are the same carrier at the same uses
// whose holds differ but fit (forgets: static data where a value claiming
// nothing is asked, or a claim forgotten), `given` at the hold asked;
// anywhere else, `given` itself. So each edge's own comparison (equality, a
// refinement, an instance, the scope's) reads what crosses through it, and
// from the stage before counting on, which reads off each edge's type what
// it passes, no edge gives a place what its type does not say it holds.
mlir::Type crossedAs(mlir::Operation *edge, mlir::Type given, mlir::Type asked);

// How far a value's claim on its own cells reaches into a field whose
// declared type is `declared`, read off the family's declaration once:
// through a field of the value's own family (a `self[...]` field); through
// a field of an `in_place` family, whose own cells are among the value's;
// and into a buffer the cell holds, its storage alone, never its elements;
// not through any other field.
FieldReach fieldReach(mlir::Type declared);

// The type at which a match binds a field of its scrutinee, as Idris binds
// a pattern variable: a declaration's field is its carrier and its own uses
// (no hold: a field holds what the value it is read from holds); the field
// is used as often as the scrutinee times its own uses, and, where its
// carrier holds references, its hold is read from the scrutinee's
// (Hold::read) at the uses the read gives it: a field of a record that is
// not unique deep is never unique deep, whatever its quantity, and one read
// at many uses claims nothing. `reach` is fieldReach of the field's
// declared type. A field used once by its type takes no grade.
mlir::Type fieldType(mlir::Type scrutinee, mlir::Type carrier, Uses uses, FieldReach reach);

// Whether a slot of `type` holds a closure, or a suspension, at any grade:
// the value's carrier says, whatever linearity a rewrite keeps.
bool isClosureType(mlir::Type type);
bool isLazyType(mlir::Type type);

// A step up a chain of definitions: from a value to the one it continues
// to, or nothing where the chain ends.
template <typename Step>
concept DefinitionStep =
    std::invocable<Step &, mlir::Value> &&
    std::same_as<std::invoke_result_t<Step &, mlir::Value>, std::optional<mlir::Value>>;

// The values from `start` along `step` until it gives nothing, `start`
// first, each passed once. A step goes to an operand of the op that
// defines a value, which dominates it in a reachable block; in an
// unreachable one an op may use its own result, so a chain may close on
// itself, and it ends where it would come back. Every walk up a chain of
// definitions is one of these.
//
// A chain closes on itself only in an unreachable block, which MLIR admits,
// so the case is essential. It is found with no set of the values passed:
// each value is the step of the one before, so once a value comes back the
// chain repeats with a fixed period. The value held at each power of two
// steps comes back exactly one period later (Brent's method), and the chain
// ends one period after the first value that comes back, each value in it
// once.
template <DefinitionStep Step>
llvm::SmallVector<mlir::Value, 4> definitionChain(mlir::Value start, Step &&step) {
  llvm::SmallVector<mlir::Value, 4> chain{start};
  std::size_t held = 0;
  std::size_t power = 1;
  for (std::optional<mlir::Value> next = step(start); next; next = step(*next)) {
    chain.push_back(*next);
    std::size_t period = chain.size() - 1 - held;
    if (*next == chain[held]) {
      std::size_t first = 0;
      while (chain[first] != chain[first + period])
        ++first;
      chain.truncate(first + period);
      return chain;
    }
    if (period == power) {
      held = chain.size() - 1;
      power *= 2;
    }
  }
  return chain;
}

// The walks through a value's changes of grade, each step an op that gives
// its operand on as its result with no run-time work. Back from a value to
// the one it was made from (linearPositions) a step keeps its operand's
// identity and sharing too (Idr_SameValue), as a value's source (sourceOf)
// and the e-graph's reading of a value cast steps, so a rewrite on the
// input finds the op the e-graph's decision found. Forward from a value to
// its uses (walkUsesThroughGrades), and back to the value it is at any
// grade (throughGrades), a step is any op that only changes the grade
// (Idr_ResultCarriesOperand), a share among them: what a share gives
// forgets what its operand claimed of its sharing, which a source does not
// follow, but it is the same cell, so a force or a read of it is one of
// the value's, and the value it was given is that value at another grade.
// The two traits name two sets of ops for that reason, and each walk reads
// its own.

// The linear positions `value` passed, `value` first and the value it was
// made from last: each step is an op that keeps its operand's value
// (Idr_SameValue) at other uses, a cast into or out of a linear position,
// so a cast's result reaches the constructor it came from however it came
// to be linear. What a value is (its constructor, a field) does not change
// on the way; whether a read may take a linear part of it is the reader's
// to decide.
llvm::SmallVector<mlir::Value, 4> linearPositions(mlir::Value value);

// The last of linearPositions: the value `value` was made from.
mlir::Value throughLinear(mlir::Value value);

// The value `value` is at any grade: back along each op that only changes
// its operand's grade (Idr_ResultCarriesOperand), the operand it carries,
// to the first value no such op gave. A chain of such ops closing on
// itself, in an unreachable block, ends where it would come back
// (definitionChain), at a value such an op gave.
mlir::Value throughGrades(mlir::Value value);

// The value `use` gives on at another grade: the result of an op that only
// changes its operand's grade (Idr_ResultCarriesOperand), where `use` is
// the operand it carries, its first; none for any other use.
std::optional<mlir::Value> regradedBy(mlir::OpOperand &use);

// A visit of a use, as MLIR's walk visits an op: it asks nothing of the
// walk, or whether the walk goes on.
template <typename Visit>
concept UseVisit =
    std::invocable<Visit &, mlir::OpOperand &> &&
    (std::same_as<std::invoke_result_t<Visit &, mlir::OpOperand &>, void> ||
     std::same_as<std::invoke_result_t<Visit &, mlir::OpOperand &>, mlir::WalkResult>);

// Every use of `value` at any grade, given to `visit`: each use of `value`,
// and of each value a change of its grade makes of it (regradedBy), that is
// no such change, until a visit interrupts the walk, which then says so.
// Each value a change makes carries one value, the one whose use made it,
// so the values form a tree rooted at `value` and each is met once. In an
// unreachable block an op may carry its own result, or a chain of changes
// close on itself; each value carrying one, a cycle the walk meets holds
// `value` itself, which the walk does not enter again.
template <UseVisit Visit>
mlir::WalkResult walkUsesThroughGrades(mlir::Value value, Visit &&visit) {
  llvm::SmallVector<mlir::Value, 4> work{value};
  while (!work.empty()) {
    mlir::Value at = work.pop_back_val();
    for (mlir::OpOperand &use : at.getUses()) {
      if (std::optional<mlir::Value> regraded = regradedBy(use)) {
        if (*regraded != value)
          work.push_back(*regraded);
        continue;
      }
      if constexpr (std::same_as<std::invoke_result_t<Visit &, mlir::OpOperand &>, void>)
        visit(use);
      else if (visit(use).wasInterrupted())
        return mlir::WalkResult::interrupt();
    }
  }
  return mlir::WalkResult::advance();
}

// What a value is made of, structurally: the same value as another (the
// result of an op that keeps its operand's value, its identity and its
// sharing, Idr_SameValue; an argument a match's region binds, the operand
// that enters it refined, a data match's scrutinee or what it forwards and
// a literal match's scrutinee in each of its regions; a loan's view and
// the owner it gives back), a field of a constructor value (an
// idr.data.field, a memo cell's included), or made here (anything else: an
// op's own result, a parameter, a region's argument).
// idr.count.share keeps its operand's value but forgets its sharing, so its
// result is made here: following it would prove a shared cell exclusive.
struct Made {};
struct Same {
  mlir::Value value;
};
struct Field {
  mlir::Value scrutinee;
  Tag tag;
  unsigned index;
};
using Source = std::variant<Made, Same, Field>;
Source sourceOf(mlir::Value value);

// The array an access reads or writes: the array a linear position was
// entered with, and the array a loan views, each the same value (sourceOf).
mlir::Value arrayRoot(mlir::Value array);

// Whether the field at `index` of a constructor value is read exactly once,
// and the value is read no other way: through its grade changes every use
// is a field read, and one of them reads `index`. Then a linear operand at
// that index moves into its one read.
bool fieldReadOnce(mlir::Value value, unsigned index);

// `value` held as `type`, its carrier at another grade, whose hold the
// value's fits (holdFits): cast into a linear position, or out of one,
// where the uses differ (idr.lin.cast); shared where only the hold does, a
// claim forgotten or static data given where a value that claims nothing
// is asked (idr.count.share); itself when the types agree.
mlir::Value heldAs(mlir::OpBuilder &b, mlir::Location loc, mlir::Value value, mlir::Type type);

// An application compares a closure's declared types with the values it is
// given. Counting grades what a value holds after the closure type is
// fixed; the uses Idris proved stay, and the carrier is the value.
template <typename Types>
concept TypeSequence = requires(Types types) {
  { *std::begin(types) } -> std::convertible_to<mlir::Type>;
  std::end(types);
};
template <TypeSequence Expected, TypeSequence Actual>
bool sameCarriers(Expected &&expected, Actual &&actual) {
  return llvm::equal(expected, actual, [](mlir::Type a, mlir::Type b) {
    return usesOf(a) == usesOf(b) && unrestricted(a) == unrestricted(b);
  });
}

// What a value of `type` holds, and how the type alone fixes the uses of
// every value of it (once, freely, or as its grade says; isLinearByType
// asks for once), as the type's ValueFactsTypeInterface answers
// (IdrInterfaces.td): every type of the dialect and every builtin type a
// value may have answers it. A type of another dialect, which only the
// lowering makes, is no value of the program and holds none of these, and
// its values are used as their grade says.
bool holdsReferences(mlir::Type type);
ByType byTypeOf(mlir::Type type);
bool isLinearByType(mlir::Type type);
bool isCounted(mlir::Type type);
bool isCellPointer(mlir::Type type);

// The types a field of a constructor may have: a word, a runtime type of
// ours, an array of mutable memory, and a value array, a ranked tensor or,
// after bufferization, its buffer.
bool isFieldType(mlir::Type type);

// An array of mutable memory: `memref<?xE, #idr.mutable>`, or `memref<E,
// #idr.mutable>` (an IORef), of a field type E at no grade.
bool isArray(mlir::Type type);

// An array of mutable memory of one dimension: one that has a length.
bool isRank1Array(mlir::Type type);

} // namespace idr

#endif // IDR_IR_GRADES_H
