// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The box of a function's row held to its body between passes: a pass that
// leaves a row short of what its body does never hands the program on.
// Each case is a program of functions that call one another, built from a
// seed: what Idris proved of each function, the loop its body holds after
// its calls (none, one that ends, or one that may not end and says so by
// idr.may_loop where its join region begins), its calls in order, and
// atoms drawn beyond what its body needs. Each row is the least the one
// writer of rows would write: those atoms, divergence for a loop that may
// not end, divergence for every member of a cycle of calls Idris did not
// prove together, and every atom of each callee's row; every call holds
// its callee's row. Then, for every function and every atom, a pass drops
// the atom from the function's row, or adds it, every call of the function
// copying the change as the one writer of rows would, and a pass after it
// notes that it ran. The pipeline stops between the two exactly when some
// row then lacks what its body needs: divergence where it holds
// idr.may_loop, and every atom of the row each of its calls holds. A
// cycle's divergence is no op's: each member's call of another member
// holds it, so a member that drops it lacks what that call needs, and a
// call of itself needs the divergence Idris's proof of the function alone
// leaves, so a member that calls itself cannot drop it either. A
// row that says too much is sound and passes. The judgement is shown
// failing each oracle planted with a fault.

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
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/OwningOpRef.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/IR/Verifier.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassManager.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallBitVector.h"
#include "llvm/ADT/SmallVector.h"

#include "gtest/gtest.h"

#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>
#include <utility>
#include <vector>

namespace {

// How a pass changes one atom of one function's row.
enum class Change : std::uint8_t { Drop, Add };

// What Idris proved of a function, as the seed draws it: nothing, or its
// own loops and recursion, in a component of its call graph.
enum class Proof : std::uint8_t { Unproved, InComponent };

// The loop a function's body holds after its calls: none; an idr.loop whose
// join region yields, so nothing repeats; or one whose join region begins
// with idr.may_loop and jumps back to itself, a loop of code Idris did not
// prove to end.
enum class Loop : std::uint8_t { None, Ends, MayNotEnd };

// Whether a cycle of calls is known to end: Idris proved every member in
// one and the same component of its own, or no call comes back, so nothing
// repeats; or it may run forever.
enum class Ending : std::uint8_t { Ends, MayNotEnd };

} // namespace

template <>
struct idr::EnumTraits<Change> {
  static constexpr std::size_t count = 2;
};

template <>
struct idr::EnumTraits<Proof> {
  static constexpr std::size_t count = 2;
};

template <>
struct idr::EnumTraits<Loop> {
  static constexpr std::size_t count = 3;
};

template <>
struct idr::EnumTraits<Ending> {
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

// What a function's loop adds to its row: divergence where it may not end,
// which its idr.may_loop declares; a loop that ends adds nothing.
constexpr EnumArray<Loop, Row> loopAtoms{{Row{}, Row{}, Row{Atom::divergence}}};

// What the one writer of rows joins into the row of each member of a
// cycle of calls: divergence where the cycle may not end.
constexpr EnumArray<Ending, Row> cycleAtoms{{Row{}, Row{Atom::divergence}}};

// The cycle of calls a function lies on: the members of its component of
// the call graph, none where no run of it calls it again; and whether the
// cycle is known to end.
struct Cycle {
  llvm::SmallBitVector members;
  Ending ending;
};

// A program, as data: what Idris proved of each function, the loop its
// body holds, the callees of its calls in order, and the atoms drawn into
// its row beyond what its body needs; then, read off those once, the cycle
// each function lies on.
struct Shape {
  std::vector<idr::Termination> terminations;
  std::vector<Loop> loops;
  std::vector<std::vector<unsigned>> calls;
  std::vector<Row> extra;
  std::vector<Cycle> cycles;
};

// The one proof that a cycle of ours ends, as the writer of rows reads it:
// Idris proved every member in one and the same component of its own.
Ending endingOf(const std::vector<idr::Termination> &terminations,
                const llvm::SmallBitVector &members) {
  return idr::match(
      terminations[static_cast<unsigned>(members.find_first())],
      [](idr::Unproved) { return Ending::MayNotEnd; },
      [&](idr::InComponent in) {
        return llvm::all_of(members.set_bits(),
                            [&](unsigned member) {
                              return terminations[member] == idr::Termination{in};
                            })
                   ? Ending::Ends
                   : Ending::MayNotEnd;
      });
}

// The cycle each function lies on, from the calls' transitive closure:
// `reaches[f]` holds every function a run of f calls through one call or
// more, closed by Warshall's rule, a case having at most five functions.
// Where f reaches itself, its cycle is every function it reaches that
// reaches it back; where it does not, nothing repeats.
std::vector<Cycle> cyclesOf(const std::vector<idr::Termination> &terminations,
                            const std::vector<std::vector<unsigned>> &calls) {
  auto functions = static_cast<unsigned>(calls.size());
  std::vector<llvm::SmallBitVector> reaches(functions, llvm::SmallBitVector(functions));
  for (unsigned f = 0; f < functions; ++f)
    for (unsigned callee : calls[f])
      reaches[f].set(callee);
  for (unsigned via = 0; via < functions; ++via)
    for (unsigned f = 0; f < functions; ++f)
      if (reaches[f].test(via))
        reaches[f] |= reaches[via];
  std::vector<Cycle> cycles;
  for (unsigned f = 0; f < functions; ++f) {
    llvm::SmallBitVector members(functions);
    if (reaches[f].test(f))
      for (unsigned g : reaches[f].set_bits())
        if (reaches[g].test(f))
          members.set(g);
    Ending ending = members.none() ? Ending::Ends : endingOf(terminations, members);
    cycles.push_back({std::move(members), ending});
  }
  return cycles;
}

// The shape of a seed: two to five functions, each with a proof and a loop
// as often as the seed's weights say, a proof in a component being in one
// of as many as the seed allows, one or two, so the members of a cycle are
// proved together or apart; each making up to as many calls as the seed
// allows; each an atom beyond its needs as often as the seed says.
Shape shapeOf(std::uint64_t seed) {
  Draws draws(seed);
  unsigned functions = 2 + draws.below(4);
  unsigned busiest = 1 + draws.below(4);
  unsigned eighths = draws.below(5);
  unsigned components = 1 + draws.below(2);
  EnumArray<Proof, unsigned> proofWeights{{1 + draws.below(4), draws.below(4)}};
  EnumArray<Loop, unsigned> loopWeights{{1 + draws.below(4), draws.below(4), draws.below(4)}};
  Shape shape;
  for (unsigned f = 0; f < functions; ++f) {
    EnumArray<Proof, idr::Termination> proofs{
        {idr::Unproved{}, idr::InComponent{draws.below(components)}}};
    shape.terminations.push_back(proofs[draws.weighted(proofWeights)]);
    shape.loops.push_back(draws.weighted(loopWeights));
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
  shape.cycles = cyclesOf(shape.terminations, shape.calls);
  return shape;
}

// The atoms function `f`'s body needs under `rows`: its loop's, every atom
// of each callee's row, which its calls hold, and, for a call of itself,
// the divergence Idris's proof of `f` alone leaves (the one derivation's
// cycle of one: none where `f` is proved, divergence otherwise).
Row needs(const Shape &shape, const std::vector<Row> &rows, unsigned f) {
  Row needed = loopAtoms[shape.loops[f]];
  llvm::SmallBitVector self(static_cast<unsigned>(rows.size()));
  self.set(f);
  for (unsigned callee : shape.calls[f])
    needed = needed | rows[callee] |
             (callee == f ? cycleAtoms[endingOf(shape.terminations, self)] : Row{});
  return needed;
}

// The least rows the one writer of rows writes: each holding its body's
// needs, its drawn atoms and its cycle's, joined until none grows.
std::vector<Row> leastRows(const Shape &shape) {
  std::vector<Row> rows(shape.loops.size());
  idr::Changed grew = idr::Changed::Yes;
  while (grew == idr::Changed::Yes) {
    grew = idr::Changed::No;
    for (unsigned f = 0; f < rows.size(); ++f)
      if (rows[f].join(needs(shape, rows, f) | shape.extra[f] |
                       cycleAtoms[shape.cycles[f].ending]) == idr::Changed::Yes)
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

// What a judge takes the body of function `f` to need under `rows`: the
// box's is `needs`.
using Needs = Row (*)(const Shape &, const std::vector<Row> &, unsigned);

// The judgement that every row holds what its body needs, by `need`.
template <Needs need>
Verdict covers(const Shape &shape, const std::vector<Row> &rows) {
  for (unsigned f = 0; f < rows.size(); ++f)
    if (!rows[f].includes(need(shape, rows, f)))
      return Verdict::Stops;
  return Verdict::Passes;
}

std::string nameOf(unsigned f) { return "f" + std::to_string(f); }

idr::TerminatesAttr attributeOf(mlir::MLIRContext &context, const idr::Termination &termination) {
  return idr::match(
      termination, [](idr::Unproved) { return idr::TerminatesAttr(); },
      [&](idr::InComponent in) { return idr::TerminatesAttr::get(&context, in); });
}

// An idr.loop of one join region, giving nothing, built at `b`'s insertion
// point: its body jumps into the join region, whose block, empty, is
// returned with `b` at its end.
mlir::Block *loopInto(mlir::OpBuilder &b, mlir::Location loc) {
  mlir::ArrayAttr binders = b.getArrayAttr({idr::IndexBindersAttr::get(b.getContext(), {})});
  auto loop = idr::LoopOp::create(b, loc, mlir::TypeRange(), mlir::ValueRange(), binders, 1u);
  mlir::Type token = b.getType<mlir::TokenType>();
  mlir::Block *body = b.createBlock(&loop.getBody(), {}, {token}, {loc});
  idr::JumpOp::create(b, loc, body->getArgument(0), mlir::ValueRange(), idr::IndexArgsAttr());
  return b.createBlock(&loop.getJoinRegions().front(), {}, {token}, {loc});
}

// Each loop built at `b`'s insertion point, which stays after it: none; a
// loop whose join region yields; a loop whose join region begins with
// idr.may_loop and jumps back to itself.
constexpr EnumArray<Loop, void (*)(mlir::OpBuilder &, mlir::Location)> loopsBuilt{
    {[](mlir::OpBuilder &, mlir::Location) {},
     [](mlir::OpBuilder &b, mlir::Location loc) {
       mlir::OpBuilder::InsertionGuard guard(b);
       loopInto(b, loc);
       idr::YieldOp::create(b, loc, mlir::ValueRange());
     },
     [](mlir::OpBuilder &b, mlir::Location loc) {
       mlir::OpBuilder::InsertionGuard guard(b);
       mlir::Block *again = loopInto(b, loc);
       idr::MayLoopOp::create(b, loc);
       idr::JumpOp::create(b, loc, again->getArgument(0), mlir::ValueRange(),
                           idr::IndexArgsAttr());
     }}};

// The program of `shape` under `rows`, at the first stage, f0 its root:
// each function taking and giving nothing, its body its calls, none in
// tail position, then its loop, then its return; each call built of its
// callee, so it holds the callee's row.
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
    loopsBuilt[shape.loops[f]](b, loc);
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
  EXPECT_EQ(judge<covers<needs>>(10, Report::Each), 0u);
}

// A loop's mark forgotten: a function whose loop may not end may drop
// divergence.
Row forgetsMarks(const Shape &shape, const std::vector<Row> &rows, unsigned f) {
  Row needed;
  for (unsigned callee : shape.calls[f])
    needed = needed | rows[callee];
  return needed;
}

// Calls forgotten: a caller may drop what its callees do.
Row forgetsCalls(const Shape &shape, const std::vector<Row> &, unsigned f) {
  return loopAtoms[shape.loops[f]];
}

// A cycle's divergence forgotten: a call of a member of the caller's own
// cycle, one that may not end, is taken to hold none, so a member may drop
// it.
Row forgetsCycles(const Shape &shape, const std::vector<Row> &rows, unsigned f) {
  const Cycle &cycle = shape.cycles[f];
  Row needed = loopAtoms[shape.loops[f]];
  for (unsigned callee : shape.calls[f])
    needed = needed |
             (cycle.members.test(callee) ? rows[callee] - cycleAtoms[cycle.ending] : rows[callee]);
  return needed;
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
  EXPECT_GT(judge<covers<forgetsMarks>>(1, Report::None), 0u);
  EXPECT_GT(judge<covers<forgetsCalls>>(1, Report::None), 0u);
  EXPECT_GT(judge<covers<forgetsCycles>>(1, Report::None), 0u);
  EXPECT_GT(judge<wantsExact>(1, Report::None), 0u);
}

} // namespace
