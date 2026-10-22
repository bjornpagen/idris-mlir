// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a run of a function may do, derived from its body's ops: the one
// derivation of a function's row and per-parameter record, which the
// function's verifier and the one writer of rows both instantiate, and the
// questions a pass asks of a row.
//
// The derivation is one fold over the body, each op read by its
// declaration through the effect system's one query API: its own effects
// projected onto the row's atoms, the runtime memory its meaning reports,
// and what it puts into a lifetime. A call is the one op whose effects are
// another function's row, so it is read apart, by the reader the
// instantiation is given: the verifier reads the call's own copy of its
// callee's row; the writer records the call and joins its callee's row
// over the program graph's components; the label solve reads a label's
// run as calls of its labels. The seed is Idris's proof: a function whose
// loops Idris did not prove end may run forever by itself.
//
// Two refinements keep a row to what a caller can see: an effect on memory
// the function acquired itself (allocated on the heap or in its frame) is
// its own; and a write through a parameter whose memory its holder alone
// reaches is the record's write part for that parameter, which the caller
// attributes to what it passed. Where a value's memory comes from is read
// through views alone (upstream's ViewLikeOpInterface), a walk as long as
// the chain of views, never a def-use search.
//
// The derivation is a rule of the function's one walk (walkFunction), so
// the verifier reads each op once for every rule of the function, the
// scopes' and the stage's beside the row's, and a solve walks a body with
// the same walk alone.
#ifndef IDR_ANALYSIS_EFFECTS_H
#define IDR_ANALYSIS_EFFECTS_H

#include "idr/IR/Effects/LLVM.h"
#include "idr/IR/Effects/Query.h"
#include "idr/IR/Families/Scope.h"
#include "idr/IR/Func.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/Support/Match.h"

#include "mlir/IR/Operation.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallBitVector.h"
#include "llvm/ADT/SmallVector.h"

#include <concepts>
#include <cstdint>
#include <optional>
#include <variant>

namespace idr::rows {

//===----------------------------------------------------------------------===//
// Questions of a row
//===----------------------------------------------------------------------===//

// Whether a row licenses deleting an unused call of it, or moving one
// where eager evaluation would not have run it: a crash and a divergence
// happen where evaluation reaches the call, so neither may be deleted or
// moved off its path. Totality removes a divergence and never a crash. The
// licence alone: the row's ordering atoms still order the call.
constexpr bool licensesDropOrMove(effects::Row row) {
  return !row.contains(effects::Atom::crash) && !row.contains(effects::Atom::divergence);
}

// Whether a call with this row may run where it would not have: it returns
// to its caller wherever it runs, and the outside cannot hold it.
constexpr bool speculatable(effects::Row row) { return (row & effects::mayNotReturn).empty(); }

// What LLVM is told of `fn`: its row's facts from the effect system's one
// table, and argument memory written where its record says it writes
// through a parameter.
effects::Told told(FuncOp fn);

//===----------------------------------------------------------------------===//
// The derivation
//===----------------------------------------------------------------------===//

// Whether a region may run more than once for each run of its function: a
// put inside one has no bound.
enum class Runs : std::uint8_t { Once, Repeatedly };

// Where an effect on a value lands, for the row of the function it is in:
// in memory the function acquired itself, which no caller sees; through a
// parameter that admits a write part, at that position among them; or
// anywhere else.
struct Local {};
struct Through {
  std::uint32_t position;
};
struct Elsewhere {};
using Lands = std::variant<Local, Through, Elsewhere>;

// What a body does: the atoms of its row, the write-admitting parameters
// it writes through, and what it puts into each put parameter.
struct Derived {
  effects::Row atoms;
  llvm::SmallBitVector written;
  llvm::SmallVector<Amount, 2> puts;
};

// The fold's state for one function: what each op contributes, read
// through the one query API and the function's parameters.
class Fold {
public:
  explicit Fold(FuncOp fn);

  // An op's own effects as it declares them, its runtime memory and what
  // it puts into a lifetime. A call is read by its reader, never here.
  void declared(mlir::Operation *op, Runs runs);
  // One effect of an op, attributed by where it lands.
  void effect(const effects::Effect &effect);
  // A write through `value`: a call's operand its callee writes through.
  void writeThrough(mlir::Value value);
  // `amount` put into `lifetime`, from a region that runs as `runs` says.
  // Only a put parameter's is the record's: a lifetime the function opened
  // is its opener's to size.
  void put(mlir::Value lifetime, Amount amount, Runs runs);
  void join(effects::Row atoms) { derived.atoms = derived.atoms | atoms; }

  // Where an effect on the memory `value` is, or is a view of, lands.
  Lands landing(mlir::Value value) const;
  // The part `value` is of this function's record: its parameter's, or
  // none for any other value.
  RecordPart partOf(mlir::Value value) const;

  const ParameterParts &parameters() const { return parts; }
  const Derived &sofar() const { return derived; }
  Derived take() && { return std::move(derived); }

private:
  // What an op that may do anything does: every atom, a write through
  // every write-admitting parameter, no bound on any put parameter.
  void anything();
  // The layouts of the function's own types, made the first time a put
  // into a put parameter needs its bytes: a function that puts into none
  // never lays out a type.
  const Layouts &layouts();

  FuncOp fn;
  ParameterParts parts;
  Derived derived;
  std::optional<Layouts> laidOut;
};

// What an op the reader reads is, to the fold: read by its declaration, or
// read already by the reader (a label's run read as calls of its labels).
enum class Read : std::uint8_t { ByDeclaration, ByReader };

// How the derivation reads what runs other functions. `call` reads each
// idr.call: the calls' copies of their callees' rows, a record of the call
// for a solve, or a label solve's own table. `other` may take any other op
// before its declaration is read.
template <class R>
concept CallReader = requires(R &reader, CallOp call, mlir::Operation *op, Fold &fold, Runs runs) {
  { reader.call(call, fold, runs) } -> std::same_as<void>;
  { reader.other(op, fold, runs) } -> std::same_as<Read>;
};

namespace detail {
// Whether `index`'s region of `op` may run more than once per run of `op`:
// as upstream's region branch interface says, and so for any other op with
// regions, whose regions no interface bounds.
Runs regionRuns(mlir::Operation *op, unsigned index);
} // namespace detail

// The derivation of `fn`'s row and record as a rule of the function's one
// walk: each op read as the walk meets it, each region entered with how
// often it runs per run of the function, which the walk's stack keeps, so
// no op asks its ancestors. It never fails: a body that does anything is
// a row that holds everything. An op that may do anything holds every
// atom already, so what the walk reads inside its regions adds nothing.
template <CallReader R>
class Derivation {
public:
  Derivation(FuncOp fn, R &reader) : fold(fn), reader(reader) {}

  // The function's body, the walk's first region, runs once per run of it;
  // any other region as its op says, and never less often than the region
  // around it.
  mlir::LogicalResult enter(mlir::Operation *op, mlir::Region &region) {
    if (runs.empty())
      runs.push_back(Runs::Once);
    else if (runs.back() == Runs::Repeatedly)
      runs.push_back(Runs::Repeatedly);
    else
      runs.push_back(detail::regionRuns(op, region.getRegionNumber()));
    return mlir::success();
  }
  mlir::LogicalResult check(mlir::Operation *op) {
    if (auto call = llvm::dyn_cast<CallOp>(op))
      reader.call(call, fold, runs.back());
    else if (reader.other(op, fold, runs.back()) == Read::ByDeclaration)
      fold.declared(op, runs.back());
    return mlir::success();
  }
  void leave() { runs.pop_back(); }

  const Fold &state() const { return fold; }
  Derived take() && { return std::move(fold).take(); }

private:
  Fold fold;
  R &reader;
  llvm::SmallVector<Runs, 8> runs;
};

// The one derivation of `fn`'s row and record, alone on the function's
// walk: what a solve reads of each body.
template <CallReader R>
Derived derive(FuncOp fn, R &reader) {
  Derivation<R> derivation(fn, reader);
  // The derivation never fails, so neither does a walk of it alone.
  (void)families::walkFunction(fn.getOperation(), derivation);
  return std::move(derivation).take();
}

// The verifier's reader: a call contributes its own copy of its callee's
// row, and a write through each operand its callee writes through. Its
// puts are checked at the call, which sees its callee.
struct CallCopies {
  void call(CallOp call, Fold &fold, Runs runs);
  Read other(mlir::Operation *, Fold &, Runs) { return Read::ByDeclaration; }
};

extern template class Derivation<CallCopies>;

// The row's rule in the verifier's walk of a function, after its own
// verifier has held the record to the signature: the derivation reading
// each call from its own copy, held after each op to the function's row,
// its untouched parameters and its put bounds, so a failure names the
// first op that breaks one, and the function's walk is read once for all
// its rules. Containment, not equality: a pass that deletes an effectful op
// leaves a row that says too much, which is sound, and no pass of another's
// can rewrite every caller's copy on the spot. A failure is the error of
// the pass that broke it, never a refusal of the program.
class Check {
public:
  explicit Check(FuncOp fn);

  mlir::LogicalResult enter(mlir::Operation *op, mlir::Region &region);
  mlir::LogicalResult check(mlir::Operation *op);
  void leave() { derivation.leave(); }

private:
  // Whether what the body did up to and with `by` stays within what the
  // function says.
  mlir::LogicalResult covered(mlir::Operation &by);

  FuncOp fn;
  CallCopies copies;
  Derivation<CallCopies> derivation;
  effects::Row row;
  llvm::ArrayRef<std::int32_t> untouched;
  llvm::SmallVector<Amount, 2> bounds;
};

static_assert(families::FunctionRule<Check>);

} // namespace idr::rows

#endif // IDR_ANALYSIS_EFFECTS_H
