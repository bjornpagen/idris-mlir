// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The box of a function's row held to its body between passes: a pass that
// leaves a row short of what its body does never hands the program on.
// Each case is a program of functions that call one another, built from a
// seed: whether Idris proved each function's own loops end, its calls in
// order, and atoms drawn beyond what its body needs; each row is the least
// that holds those and every atom of each callee's row, and every call
// holds its callee's row. Then, for every function and every atom, a pass
// drops the atom from the function's row, or adds it, every call of the
// function copying the change as the one writer of rows would, and a pass
// after it notes that it ran. The pipeline stops between the two exactly
// when some row then lacks what its body needs: divergence where Idris did
// not prove the function's loops end, and every atom of the row each of
// its calls holds. A row that says too much is sound and passes. The
// judgement is shown failing each oracle planted with a fault.

#include "idr/IR/Effects/Vocabulary.h"
#include "idr/IR/Func.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Changed.h"
#include "idr/Support/Enum.h"
#include "idr/Support/Match.h"
#include "idr/Testing/Draws.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/OwningOpRef.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/IR/Verifier.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassManager.h"
#include "llvm/ADT/SmallVector.h"

#include "gtest/gtest.h"

#include <cstddef>
#include <cstdint>
#include <iterator>
#include <memory>
#include <string>
#include <utility>
#include <vector>

namespace {

// How a pass changes one atom of one function's row.
enum class Change : std::uint8_t { Drop, Add };

} // namespace

template <>
struct idr::EnumTraits<Change> {
  static constexpr std::size_t count = 2;
};

namespace {

using idr::EnumArray;
using idr::box::Draws;
using idr::effects::Atom;
using idr::effects::Row;

// The number of seeds the box builds a program from.
constexpr std::uint64_t seeds = 200;

constexpr EnumArray<Change, Row (*)(Row, Atom)> changes{
    {[](Row row, Atom atom) { return row - Row{atom}; },
     [](Row row, Atom atom) { return row | Row{atom}; }}};
constexpr EnumArray<Change, const char *> changeNames{{"dropped", "added"}};

// A program, as data: what is known of each function's own loops, the
// callees of its calls in order, and the atoms drawn into its row beyond
// what its body needs.
struct Shape {
  std::vector<idr::Termination> terminations;
  std::vector<std::vector<unsigned>> calls;
  std::vector<Row> extra;
};

// The shape of a seed: two to five functions, each making up to as many
// calls as the seed allows, each an atom beyond its needs as often as the
// seed says.
Shape shapeOf(std::uint64_t seed) {
  Draws draws(seed);
  unsigned functions = 2 + draws.below(4);
  unsigned busiest = 1 + draws.below(4);
  unsigned eighths = draws.below(5);
  Shape shape;
  for (unsigned f = 0; f < functions; ++f) {
    const idr::Termination known[] = {idr::Unproved{}, idr::InComponent{f}, idr::Acyclic{}};
    shape.terminations.push_back(known[draws.below(std::size(known))]);
    std::vector<unsigned> callees;
    for (unsigned c = draws.below(busiest); c > 0; --c)
      callees.push_back(draws.below(functions));
    shape.calls.push_back(std::move(callees));
    Row extra;
    for (Atom atom : idr::allOf<Atom>())
      if (draws.below(8) < eighths)
        (void)extra.join({atom});
    shape.extra.push_back(extra);
  }
  return shape;
}

// What a function's loops add to its row: divergence, unless Idris proved
// they end or a pass made the function with none.
Row seedOf(const idr::Termination &termination) {
  return idr::match(
      termination, [](idr::Unproved) { return Row{Atom::divergence}; },
      [](idr::InComponent) { return Row{}; }, [](idr::Acyclic) { return Row{}; });
}

// The atoms function `f`'s body needs under `rows`: its loops' and every
// atom of each callee's row, which its calls hold.
Row needs(const Shape &shape, const std::vector<Row> &rows, unsigned f) {
  Row needed = seedOf(shape.terminations[f]);
  for (unsigned callee : shape.calls[f])
    needed = needed | rows[callee];
  return needed;
}

// The least rows holding each body's needs and its drawn atoms.
std::vector<Row> leastRows(const Shape &shape) {
  std::vector<Row> rows(shape.terminations.size());
  idr::Changed grew = idr::Changed::Yes;
  while (grew == idr::Changed::Yes) {
    grew = idr::Changed::No;
    for (unsigned f = 0; f < rows.size(); ++f)
      if (rows[f].join(needs(shape, rows, f) | shape.extra[f]) == idr::Changed::Yes)
        grew = idr::Changed::Yes;
  }
  return rows;
}

// Whether the pipeline hands the program on.
enum class Verdict : std::uint8_t { Passes, Stops };

// What a judge takes for the truth of a program under `rows`. The box's
// is that every row holds what its body needs; a mutant's is wrong, and
// the judge must say so.
using Oracle = Verdict (*)(const Shape &, const std::vector<Row> &);

Verdict covers(const Shape &shape, const std::vector<Row> &rows) {
  for (unsigned f = 0; f < rows.size(); ++f)
    if (!rows[f].includes(needs(shape, rows, f)))
      return Verdict::Stops;
  return Verdict::Passes;
}

std::string nameOf(unsigned f) { return "f" + std::to_string(f); }

idr::TerminatesAttr attributeOf(mlir::MLIRContext &context, const idr::Termination &termination) {
  return idr::match(
      termination, [](idr::Unproved) { return idr::TerminatesAttr(); },
      [&](idr::InComponent in) { return idr::TerminatesAttr::get(&context, in); },
      [&](idr::Acyclic acyclic) { return idr::TerminatesAttr::get(&context, acyclic); });
}

// The program of `shape` under `rows`, at the first stage, f0 its root:
// each function taking and giving nothing, its body its calls, none in
// tail position, then its return; each call built of its callee, so it
// holds the callee's row.
mlir::OwningOpRef<mlir::ModuleOp> programOf(mlir::MLIRContext &context, const Shape &shape,
                                            const std::vector<Row> &rows) {
  mlir::OpBuilder b(&context);
  mlir::Location loc = b.getUnknownLoc();
  mlir::OwningOpRef<mlir::ModuleOp> module = mlir::ModuleOp::create(loc);
  b.setInsertionPointToEnd(module->getBody());
  auto program = idr::ProgramOp::create(b, loc, "rows", nameOf(0), idr::Stage::First);
  b.setInsertionPointToEnd(&program.getBody().front());
  std::vector<idr::FuncOp> functions;
  for (unsigned f = 0; f < rows.size(); ++f) {
    mlir::OperationState state(loc, idr::FuncOp::getOperationName());
    auto &properties = state.getOrAddProperties<idr::FuncOp::Properties>();
    properties.sym_name = b.getStringAttr(nameOf(f));
    properties.function_type = mlir::TypeAttr::get(b.getFunctionType({}, {}));
    properties.row = rows[f];
    properties.terminates = attributeOf(context, shape.terminations[f]);
    state.addRegion();
    functions.push_back(llvm::cast<idr::FuncOp>(b.create(state)));
  }
  for (unsigned f = 0; f < rows.size(); ++f) {
    b.createBlock(&functions[f].getBody());
    for (unsigned callee : shape.calls[f])
      idr::CallOp::create(b, loc, functions[callee], idr::IndexArgsAttr(), mlir::ValueRange(),
                          idr::TailKind::nontail);
    idr::ReturnOp::create(b, loc, mlir::ValueRange());
  }
  return module;
}

// Writes one function's row, and every call of it copies what it holds of
// its callee, as the one writer of rows leaves a function and its calls.
struct Rewrite : mlir::PassWrapper<Rewrite, mlir::OperationPass<idr::ProgramOp>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(Rewrite)

  Rewrite(mlir::StringAttr function, Row row) : function(function), row(row) {}

  void runOnOperation() override {
    idr::ProgramOp program = getOperation();
    auto fn = llvm::cast<idr::FuncOp>(mlir::SymbolTable::lookupSymbolIn(program, function));
    fn.setRow(row);
    program.walk([&](idr::CallOp call) {
      if (call.getCalleeAttr().getAttr() == function)
        call.copyCallee(fn);
    });
  }

  mlir::StringAttr function;
  Row row;
};

// Whether a pass ran.
enum class Ran : std::uint8_t { No, Yes };

// Notes that it ran: the pass after the rewrite.
struct Next : mlir::PassWrapper<Next, mlir::OperationPass<idr::ProgramOp>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(Next)

  explicit Next(Ran &ran) : ran(ran) {}
  void runOnOperation() override { ran = Ran::Yes; }

  Ran &ran;
};

// What a pipeline of the rewrite and the pass after it does on a copy of
// `module`: whether it handed the program on, and whether the pass after
// the rewrite ran.
struct Outcome {
  Verdict verdict;
  Ran next;
};

Outcome rewritten(mlir::ModuleOp module, mlir::StringAttr function, Row row) {
  mlir::OwningOpRef<mlir::ModuleOp> copy = module.clone();
  Ran ran = Ran::No;
  mlir::PassManager pm(module.getContext());
  mlir::OpPassManager &program = pm.nest<idr::ProgramOp>();
  program.addPass(std::make_unique<Rewrite>(function, row));
  program.addPass(std::make_unique<Next>(ran));
  Verdict verdict = mlir::succeeded(pm.run(*copy)) ? Verdict::Passes : Verdict::Stops;
  return {verdict, ran};
}

const char *spelled(Verdict verdict) { return verdict == Verdict::Passes ? "passes" : "stops"; }

// Every change of one atom of one function's row in `module`, the program
// of `shape` under `rows`, where the pipeline disagrees with `oracle`, or
// where the pass after the rewrite ran though the pipeline stopped or did
// not though it went on: a line each.
template <Oracle oracle>
std::string disagreements(mlir::ModuleOp module, const Shape &shape, const std::vector<Row> &rows) {
  std::string lines;
  for (unsigned f = 0; f < rows.size(); ++f)
    for (Atom atom : idr::allOf<Atom>())
      for (Change change : idr::allOf<Change>()) {
        std::vector<Row> changed = rows;
        changed[f] = changes[change](rows[f], atom);
        Outcome outcome = rewritten(
            module, mlir::StringAttr::get(module.getContext(), nameOf(f)), changed[f]);
        Ran next = outcome.verdict == Verdict::Passes ? Ran::Yes : Ran::No;
        if (outcome.verdict == oracle(shape, changed) && outcome.next == next)
          continue;
        lines += "\n  " + nameOf(f) + "'s row with " +
                 std::string(idr::EnumTraits<Atom>::names[static_cast<std::size_t>(atom)]) + " " +
                 changeNames[change] + ": the pipeline " + spelled(outcome.verdict) +
                 (outcome.next == next ? "" : ", and the pass after the rewrite ran where it "
                                              "should not or did not where it should");
      }
  return lines;
}

// Whether a failing case is reported: by the box's own judgement, each;
// by a mutant's, none, since a mutant must fail.
enum class Report : std::uint8_t { Each, None };

// The cases, over every seed up to `limit` of them, where the pipeline
// disagrees with `oracle` on the program as built or after a change of one
// atom of one row. Each is reported, when `report` says so, with its seed
// and what it disagrees on.
template <Oracle oracle>
unsigned judge(unsigned limit, Report report) {
  mlir::MLIRContext context;
  context.disableMultithreading();
  context.loadDialect<idr::IdrDialect>();
  // A refusal is the box's to expect, not to print.
  mlir::ScopedDiagnosticHandler quiet(&context, [](mlir::Diagnostic &) { return mlir::success(); });
  unsigned failures = 0;
  for (std::uint64_t seed = 1; seed <= seeds && failures < limit; ++seed) {
    Shape shape = shapeOf(seed);
    std::vector<Row> rows = leastRows(shape);
    mlir::OwningOpRef<mlir::ModuleOp> module = programOf(context, shape, rows);
    Verdict built = mlir::succeeded(mlir::verify(*module)) ? Verdict::Passes : Verdict::Stops;
    std::string why = built != oracle(shape, rows)
                          ? "\n  the program as built " + std::string(spelled(built))
                          : disagreements<oracle>(*module, shape, rows);
    if (why.empty())
      continue;
    ++failures;
    if (report == Report::Each)
      ADD_FAILURE() << "seed " << seed << ":" << why;
  }
  return failures;
}

TEST(Rows, ThePipelineStopsExactlyWhereARowLacksWhatItsBodyNeeds) {
  EXPECT_EQ(judge<covers>(10, Report::Each), 0u);
}

// Idris's proof forgotten: a function it did not prove may drop
// divergence.
Verdict forgetsLoops(const Shape &shape, const std::vector<Row> &rows) {
  for (unsigned f = 0; f < rows.size(); ++f) {
    Row needed;
    for (unsigned callee : shape.calls[f])
      needed = needed | rows[callee];
    if (!rows[f].includes(needed))
      return Verdict::Stops;
  }
  return Verdict::Passes;
}

// Calls forgotten: a caller may drop what its callees do.
Verdict forgetsCalls(const Shape &shape, const std::vector<Row> &rows) {
  for (unsigned f = 0; f < rows.size(); ++f)
    if (!rows[f].includes(seedOf(shape.terminations[f])))
      return Verdict::Stops;
  return Verdict::Passes;
}

// Equality taken for containment: a row that says too much is refused.
Verdict wantsExact(const Shape &shape, const std::vector<Row> &rows) {
  for (unsigned f = 0; f < rows.size(); ++f)
    if (rows[f] != needs(shape, rows, f))
      return Verdict::Stops;
  return Verdict::Passes;
}

// The judgement can fail: each oracle with a planted fault disagrees with
// the pipeline on some case.
TEST(Rows, EachMutantOracleIsCaught) {
  EXPECT_GT(judge<forgetsLoops>(1, Report::None), 0u);
  EXPECT_GT(judge<forgetsCalls>(1, Report::None), 0u);
  EXPECT_GT(judge<wantsExact>(1, Report::None), 0u);
}

} // namespace
