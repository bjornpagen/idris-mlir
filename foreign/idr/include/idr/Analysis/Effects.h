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
// The walk keeps its own stack, so no recursion follows the nesting.
#ifndef IDR_ANALYSIS_EFFECTS_H
#define IDR_ANALYSIS_EFFECTS_H

#include "idr/IR/Effects/LLVM.h"
#include "idr/IR/Effects/Query.h"
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

// Whether an op's declaration bounds what it does: an op of another
// dialect that declares nothing and is not recursive may do anything,
// so its regions are not read.
enum class Declares : std::uint8_t { Bounded, Anything };

// The fold's state for one function: what each op contributes, read
// through the one query API and the function's parameters.
class Fold {
public:
  explicit Fold(FuncOp fn);

  // An op's own effects as it declares them, its runtime memory and what
  // it puts into a lifetime. A call is read by its reader, never here.
  Declares declared(mlir::Operation *op, Runs runs);
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
// before its declaration is read; `after` sees the fold once each op is
// read, for a reader that names the op a fact came from.
template <class R>
concept CallReader = requires(R &reader, CallOp call, mlir::Operation *op, Fold &fold, Runs runs) {
  { reader.call(call, fold, runs) } -> std::same_as<void>;
  { reader.other(op, fold, runs) } -> std::same_as<Read>;
  { reader.after(op, fold) } -> std::same_as<void>;
};

namespace detail {
// Whether `index`'s region of `op` may run more than once per run of `op`:
// as upstream's region branch interface says, and so for any other op with
// regions, whose regions no interface bounds.
Runs regionRuns(mlir::Operation *op, unsigned index);
} // namespace detail

// The one derivation of `fn`'s row and record, every op of its body read
// once, in order, each region's ops after the op that holds it.
template <CallReader R>
Derived derive(FuncOp fn, R &reader) {
  Fold fold(fn);
  struct Level {
    mlir::Block::iterator at, end;
    Runs runs;
  };
  llvm::SmallVector<Level, 8> stack;
  for (mlir::Block &block : llvm::reverse(fn.getBody()))
    stack.push_back({block.begin(), block.end(), Runs::Once});
  while (!stack.empty()) {
    Level &level = stack.back();
    if (level.at == level.end) {
      stack.pop_back();
      continue;
    }
    mlir::Operation *op = &*level.at++;
    Runs runs = level.runs;
    if (auto call = llvm::dyn_cast<CallOp>(op)) {
      reader.call(call, fold, runs);
      reader.after(op, fold);
      continue;
    }
    if (reader.other(op, fold, runs) == Read::ByDeclaration &&
        fold.declared(op, runs) == Declares::Anything) {
      reader.after(op, fold);
      continue;
    }
    reader.after(op, fold);
    // Pushed last region first, so the first is read first.
    for (unsigned index = op->getNumRegions(); index-- > 0;) {
      Runs inner = runs == Runs::Repeatedly ? Runs::Repeatedly : detail::regionRuns(op, index);
      for (mlir::Block &block : llvm::reverse(op->getRegion(index)))
        stack.push_back({block.begin(), block.end(), inner});
    }
  }
  return std::move(fold).take();
}

// The verifier's reader: a call contributes its own copy of its callee's
// row, and a write through each operand its callee writes through. Its
// puts are checked at the call, which sees its callee.
struct CallCopies {
  void call(CallOp call, Fold &fold, Runs runs);
  Read other(mlir::Operation *, Fold &, Runs) { return Read::ByDeclaration; }
  void after(mlir::Operation *, Fold &) {}
};

extern template Derived derive<CallCopies>(FuncOp fn, CallCopies &reader);

// `fn`'s row and record cover what its body does: the function's region
// verifier, after its own verifier has held the record to the signature.
// A failure names the function, what it lacks and the op that needs it; it
// is the error of the pass that broke it, never a refusal of the program.
mlir::LogicalResult verify(FuncOp fn);

} // namespace idr::rows

#endif // IDR_ANALYSIS_EFFECTS_H
