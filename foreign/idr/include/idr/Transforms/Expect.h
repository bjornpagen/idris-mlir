// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-expect: properties of a module that tests state by name, instead of
// matching the ops that happen to show them. Each property is a check that
// reports every place it fails, one error each, and changes nothing. What a
// property needs of the module beyond its ops (the symbol table, the cells'
// layouts) it asks of the analysis manager, so properties that ask the same
// share one answer and the pass keeps nothing between runs. The table of
// properties (Lookup.cpp) is the one list of what idr-expect checks: a row
// holds a property's name once, pairs it with the shape of its argument,
// which the row's type checks, and says what it checks.
//
// A request's argument is read once, before its check runs, into the typed
// value of its shape below: a function named, a count, a list, a module
// read from a file. A text that does not have the shape is refused there,
// in the one wording every property shares, and an `@f` that names no
// function is refused there too; a check takes the typed value and never
// reads text.
//
// A property is stated of the program: the functions the module's
// idr.program holds, under its symbol table, before idr-lower; the
// functions of the module itself after it, which moves them out and erases
// the op. So one property reads a module of either stage.
//
// `@f` names every function made from the code the programmer wrote as f:
// a function whose symbol is f, and a function whose own location names f.
// Emit gives each function, lambdas and delays included, the name of its
// Idris definition; a copy a pass makes keeps its original's location; and
// deduplication fuses the locations of the functions it merges into the
// one it keeps. So a property stated of f holds of every copy of f's code,
// however the passes named it. A hand-written module names a function by
// its symbol, or gives it `loc("f")` where its copies must be found too.
#ifndef IDR_TRANSFORMS_EXPECT_H
#define IDR_TRANSFORMS_EXPECT_H

#include "idr/IR/IdrDialect.h"

#include "mlir/Dialect/LLVMIR/LLVMAttrs.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/OwningOpRef.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/CallInterfaces.h"
#include "mlir/Interfaces/FunctionInterfaces.h"
#include "mlir/Pass/AnalysisManager.h"
#include "mlir/Pass/Pass.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"

#include <cstdint>
#include <optional>
#include <string>
#include <variant>

namespace idr {
#define GEN_PASS_DECL_IDREXPECT
#include "idr/Transforms/Passes.h.inc"

// Registers test-idr-facts, the pass that reports what the dialect answers
// about each op of a function's body as a remark, for the effects' tests.
void registerFactsTestPass();
} // namespace idr

namespace idr::expect {

//===----------------------------------------------------------------------===//
// Arguments
//===----------------------------------------------------------------------===//

// A request's argument as its parsers read it: the text after `=` (empty
// when there is none), the property that asks, and the shape the whole text
// must have, which a parser of one of its parts reports for the whole.
struct Written {
  mlir::ModuleOp module;
  llvm::StringRef property;
  llvm::StringRef text;
  llvm::StringRef form;
  // The one refusal of a text without its shape, at the module:
  // `idr-expect: <property>=<text> does not read as <property>=<form>`, the
  // property alone where the shape is no argument.
  mlir::LogicalResult malformed() const;
};

// Each shape below holds its `form`, the text its refusal shows, and the
// one parser of it, which reads `text`, all or part of `written.text`.

// No argument: the property alone.
struct Nothing {
  static constexpr llvm::StringLiteral form = "";
  static mlir::FailureOr<Nothing> parse(const Written &written, llvm::StringRef text);
};

// `@f`: f, without its `@`, and every function made from it (`names`), at
// least one: a name no function answers to is refused by the parser.
struct Functions {
  static constexpr llvm::StringLiteral form = "@f";
  llvm::StringRef name;
  llvm::SmallVector<mlir::FunctionOpInterface> functions;
  static mlir::FailureOr<Functions> parse(const Written &written, llvm::StringRef text);
};

// `@f` or nothing: the property is stated of the functions @f names, or of
// the whole module.
struct Roots {
  static constexpr llvm::StringLiteral form = "[@f]";
  std::optional<Functions> scope;
  // The ops a property of ops is checked under: each function @f names, or
  // the module.
  llvm::SmallVector<mlir::Operation *> roots(mlir::ModuleOp module) const;
  // Where the property is stated, for its errors: ` in @f`, or nothing.
  std::string in() const;
  static mlir::FailureOr<Roots> parse(const Written &written, llvm::StringRef text);
};

// `@f`: a name a check matches against a symbol or by `names`, which may
// name no function: a callee (of the runtime's, after lowering), a label's
// function, a function every call of which is gone.
struct Symbol {
  static constexpr llvm::StringLiteral form = "@f";
  llvm::StringRef name;
  static mlir::FailureOr<Symbol> parse(const Written &written, llvm::StringRef text);
};

// `@f:@g`: the functions @f names, and the name @g of what they call or
// reach.
struct Pair {
  static constexpr llvm::StringLiteral form = "@f:@g";
  Functions caller;
  Symbol callee;
  static mlir::FailureOr<Pair> parse(const Written &written, llvm::StringRef text);
};

// `@f:@g`: the functions each of the two names.
struct TwoFunctions {
  static constexpr llvm::StringLiteral form = "@f:@g";
  Functions first;
  Functions second;
  static mlir::FailureOr<TwoFunctions> parse(const Written &written, llvm::StringRef text);
};

// `@f:<n>`: the functions @f names, and a count.
struct CountOf {
  static constexpr llvm::StringLiteral form = "@f:<n>";
  Functions function;
  unsigned count;
  static mlir::FailureOr<CountOf> parse(const Written &written, llvm::StringRef text);
};

// `@f` or `@f:<n>`: the functions @f names, and how many loops each has:
// exactly the count, or, with none written, some.
struct Loops {
  static constexpr llvm::StringLiteral form = "@f[:<n>]";
  Functions function;
  std::optional<unsigned> count;
  static mlir::FailureOr<Loops> parse(const Written &written, llvm::StringRef text);
};

// `<n>`: a bound.
struct Bound {
  static constexpr llvm::StringLiteral form = "<n>";
  uint64_t bound;
  static mlir::FailureOr<Bound> parse(const Written &written, llvm::StringRef text);
};

// `@f:[@g, ...]`: the functions @f names, and a list of names, in its
// order; `[]` is the empty list.
struct Listed {
  static constexpr llvm::StringLiteral form = "@f:[@g, ...]";
  Functions function;
  llvm::SmallVector<Symbol> names;
  static mlir::FailureOr<Listed> parse(const Written &written, llvm::StringRef text);
};

// A place of a function's signature: a result or a parameter, by index.
struct Position {
  enum class Kind { Result, Arg } kind;
  unsigned index;
};

// `@f:<position>:[@g, ...]`, the position written `result` (result 0),
// `result<n>` or `arg<n>`: the functions @f names, the place, and the list.
struct Labels {
  static constexpr llvm::StringLiteral form = "@f:<position>:[@g, ...]";
  Functions function;
  Position position;
  llvm::SmallVector<Symbol> names;
  static mlir::FailureOr<Labels> parse(const Written &written, llvm::StringRef text);
};

// What a test writes a value to be, read in this order: `_`, a value
// computed at run time, no constant (a fold that must not happen); an
// integer of any width, or a float, by its value; anything else an
// attribute as MLIR writes it (`#idr.big<-4>`, `"abc"`, `true`,
// `#idr.con<...>`), read alone, outside the module's text, so a
// constructor writes its data type with its body, not by the module's
// alias. An item may be wrapped in parentheses, which keep the commas in it
// from splitting the list of properties; the items of a list are split only
// outside brackets and quotes.
struct Computed {};
using Item = std::variant<Computed, int64_t, double, mlir::Attribute>;

// `@f:<v>/<v>...`: the functions @f names, and one item per result.
struct ReturnedValues {
  static constexpr llvm::StringLiteral form = "@f:<v>/<v>...";
  Functions function;
  llvm::SmallVector<Item> values;
  static mlir::FailureOr<ReturnedValues> parse(const Written &written, llvm::StringRef text);
};

// `@f:<v>+<v>...`: the functions @f names, and the items one result may be.
struct PathValues {
  static constexpr llvm::StringLiteral form = "@f:<v>+<v>...";
  Functions function;
  llvm::SmallVector<Item> values;
  static mlir::FailureOr<PathValues> parse(const Written &written, llvm::StringRef text);
};

// `@f:<n>/<n>...`: the functions @f names, and one parameter's position per
// result.
struct ReturnedArguments {
  static constexpr llvm::StringLiteral form = "@f:<n>/<n>...";
  Functions function;
  llvm::SmallVector<unsigned> positions;
  static mlir::FailureOr<ReturnedArguments> parse(const Written &written, llvm::StringRef text);
};

// `@f:<e>+<e>...`: the functions @f names, and the set of effects the cases
// written make, of io, crash and diverge; `none`, the empty set.
struct EffectsOf {
  static constexpr llvm::StringLiteral form = "@f:<e>+<e>...";
  Functions function;
  Effect effects;
  static mlir::FailureOr<EffectsOf> parse(const Written &written, llvm::StringRef text);
};

// `<file>`: the module the file holds, read into the module's context, so a
// type it names is the one the module names. A file that cannot be read is
// refused by the parser.
struct Module {
  static constexpr llvm::StringLiteral form = "<file>";
  mlir::OwningOpRef<mlir::ModuleOp> op;
  static mlir::FailureOr<Module> parse(const Written &written, llvm::StringRef text);
};

// `@f:<file>`: the functions @f names, and the module the file holds.
struct FunctionsAndModule {
  static constexpr llvm::StringLiteral form = "@f:<file>";
  Functions function;
  Module module;
  static mlir::FailureOr<FunctionsAndModule> parse(const Written &written, llvm::StringRef text);
};

// `<stage>`: a stage of the program, as its idr.program writes it.
struct StageIs {
  static constexpr llvm::StringLiteral form = "<stage>";
  Stage stage;
  static mlir::FailureOr<StageIs> parse(const Written &written, llvm::StringRef text);
};

// `@f:<type>`: the functions @f names, and a function type as MLIR writes
// it.
struct TypeOf {
  static constexpr llvm::StringLiteral form = "@f:<type>";
  Functions function;
  mlir::Type type;
  static mlir::FailureOr<TypeOf> parse(const Written &written, llvm::StringRef text);
};

// `@f:<cc>`: the functions @f names, and a calling convention as LLVM
// spells it (ccc, tailcc, ...).
struct ConventionOf {
  static constexpr llvm::StringLiteral form = "@f:<cc>";
  Functions function;
  mlir::LLVM::cconv::CConv convention;
  static mlir::FailureOr<ConventionOf> parse(const Written &written, llvm::StringRef text);
};

//===----------------------------------------------------------------------===//
// Properties
//===----------------------------------------------------------------------===//

// What a check is given: the module, the pass's analyses, the name it was
// asked by, which its errors carry, and its argument, read.
template <typename A> struct Request {
  mlir::ModuleOp module;
  mlir::AnalysisManager &analyses;
  llvm::StringRef property;
  const A &argument;
};

// A row of the table: a property's name, and what checks a request of it,
// the text after `=` (empty when there is none) read by its argument's
// parser, then its check run. Fails when it reported an error.
struct Property {
  llvm::StringRef name;
  mlir::LogicalResult (*run)(mlir::ModuleOp module, mlir::AnalysisManager &analyses,
                             llvm::StringRef property, llvm::StringRef text);
};

// The row of `Check` under `name`: its argument is of shape A, so a check
// paired with an argument of another shape does not compile.
template <typename A, mlir::LogicalResult (*Check)(const Request<A> &)>
constexpr Property property(llvm::StringRef name) {
  return {name, [](mlir::ModuleOp module, mlir::AnalysisManager &analyses, llvm::StringRef asked,
                   llvm::StringRef text) -> mlir::LogicalResult {
            mlir::FailureOr<A> argument = A::parse(Written{module, asked, text, A::form}, text);
            if (mlir::failed(argument))
              return mlir::failure();
            return Check(Request<A>{module, analyses, asked, *argument});
          }};
}

// The row of the property named `name`, or null when there is none.
const Property *lookup(llvm::StringRef name);

// The error that `property` fails at `loc`, to which the caller adds what
// was found: `expected <property>: <what>`.
mlir::InFlightDiagnostic fail(mlir::Location loc, llvm::StringRef property);

// The function that holds `op` (or is it), as `@name`, or "the module".
std::string where(mlir::Operation *op);

// The op whose symbol table holds the program's functions: the module's
// idr.program, or the module once lowering has erased it.
mlir::Operation *programOf(mlir::ModuleOp module);

// The program's functions, in their order.
llvm::SmallVector<mlir::FunctionOpInterface> functionsOf(mlir::ModuleOp module);

// The program's symbol table, built once for every property that asks.
mlir::SymbolTable &symbolsOf(mlir::ModuleOp module, mlir::AnalysisManager &analyses);

// Whether `fn` is made from the code written as `f`: its symbol is `f`, or
// its own location names `f`.
bool names(mlir::FunctionOpInterface fn, llvm::StringRef f);

// The functions the body of `fn` names by a symbol use (a call, a closure,
// a constant), in the order the walk meets them, each once.
llvm::SmallVector<mlir::Operation *> callees(mlir::SymbolTable &symbols, mlir::Operation *fn);

// The cycles among `nodes` by `edges`, an edge to a node outside `nodes`
// dropped: each strongly connected component of two or more, or of one
// that refers to itself, callees first.
llvm::SmallVector<llvm::SmallVector<mlir::Operation *>>
cycles(llvm::ArrayRef<mlir::Operation *> nodes,
       llvm::function_ref<llvm::SmallVector<mlir::Operation *>(mlir::Operation *)> edges);

// Whether `call` calls `g`: its callee's symbol is g, or it calls a
// function of `symbols` made from the code written as g (`names`).
bool callsNamed(mlir::CallOpInterface call, const Symbol &g, mlir::SymbolTable &symbols);

// How many places of `fn` may crash: an idr op that never returns, a
// guard, or a call of the LLVM dialect that never returns (the call says
// so, or its callee in `symbols`).
unsigned crashSitesOf(mlir::FunctionOpInterface fn, mlir::SymbolTable &symbols);

// The checks, by the shape of their argument; the table says what each
// checks. quantitiesKept and foldsBalanced are the contracts' too, which
// call them with the module before a pass and nothing.
mlir::LogicalResult noClosures(const Request<Roots> &);
mlir::LogicalResult labels(const Request<Labels> &);
mlir::LogicalResult noHeapAllocation(const Request<Roots> &);
mlir::LogicalResult oneClone(const Request<Symbol> &);
mlir::LogicalResult specializedOnce(const Request<Functions> &);
mlir::LogicalResult notCalled(const Request<Symbol> &);
mlir::LogicalResult quantitiesKept(const Request<Module> &);
mlir::LogicalResult reusesInPlace(const Request<Functions> &);
mlir::LogicalResult movesOut(const Request<Roots> &);
mlir::LogicalResult countsNothing(const Request<Functions> &);
mlir::LogicalResult noGuards(const Request<Functions> &);
mlir::LogicalResult testsNothing(const Request<Functions> &);
mlir::LogicalResult exclusiveCopy(const Request<Functions> &);
mlir::LogicalResult resetsUnshared(const Request<Roots> &);
mlir::LogicalResult reusesEveryCell(const Request<Functions> &);
mlir::LogicalResult contified(const Request<Nothing> &);
mlir::LogicalResult outputFused(const Request<Roots> &);
mlir::LogicalResult foldsBalanced(const Request<Nothing> &);
mlir::LogicalResult folded(const Request<Functions> &);
mlir::LogicalResult constantStack(const Request<Functions> &);
mlir::LogicalResult tailCalls(const Request<Pair> &);
mlir::LogicalResult countedLoop(const Request<Functions> &);
mlir::LogicalResult wordLoop(const Request<Functions> &);
mlir::LogicalResult structuredLoops(const Request<Roots> &);
mlir::LogicalResult typedReads(const Request<Functions> &);
mlir::LogicalResult inPlace(const Request<Roots> &);
mlir::LogicalResult fused(const Request<Functions> &);
mlir::LogicalResult largestFunction(const Request<Bound> &);
mlir::LogicalResult vectorized(const Request<Roots> &);
mlir::LogicalResult narrowedLanes(const Request<Roots> &);
mlir::LogicalResult matches(const Request<Functions> &);
mlir::LogicalResult matchesNothing(const Request<Functions> &);
mlir::LogicalResult forcesSome(const Request<Functions> &);
mlir::LogicalResult forcesNothing(const Request<Functions> &);
mlir::LogicalResult buildsSome(const Request<Functions> &);
mlir::LogicalResult buildsNothing(const Request<Functions> &);
mlir::LogicalResult readsFields(const Request<Functions> &);
mlir::LogicalResult readsNoFields(const Request<Functions> &);
mlir::LogicalResult applies(const Request<Functions> &);
mlir::LogicalResult neverReturns(const Request<Functions> &);
mlir::LogicalResult calls(const Request<Pair> &);
mlir::LogicalResult neverCalls(const Request<Pair> &);
mlir::LogicalResult callsClosed(const Request<Pair> &);
mlir::LogicalResult returnsConstants(const Request<ReturnedValues> &);
mlir::LogicalResult returnsOnPaths(const Request<PathValues> &);
mlir::LogicalResult returnsArguments(const Request<ReturnedArguments> &);
mlir::LogicalResult buildsWhereUsed(const Request<Functions> &);
mlir::LogicalResult callsWhereUsed(const Request<Pair> &);
mlir::LogicalResult matchesOnce(const Request<Functions> &);
mlir::LogicalResult crashesBeforeOutput(const Request<Functions> &);
mlir::LogicalResult parametersUsed(const Request<Functions> &);
mlir::LogicalResult resultsUsed(const Request<Functions> &);
mlir::LogicalResult regionsDistinct(const Request<Functions> &);
mlir::LogicalResult checksEveryPath(const Request<Functions> &);
mlir::LogicalResult growsNothing(const Request<FunctionsAndModule> &);
mlir::LogicalResult callOrder(const Request<Listed> &);
mlir::LogicalResult callsDistinct(const Request<Pair> &);
mlir::LogicalResult callsRead(const Request<Pair> &);
mlir::LogicalResult callsOnly(const Request<Listed> &);
mlir::LogicalResult directCalls(const Request<Roots> &);
mlir::LogicalResult crashSites(const Request<CountOf> &);
mlir::LogicalResult lowered(const Request<Roots> &);
mlir::LogicalResult inLLVM(const Request<Nothing> &);
mlir::LogicalResult signature(const Request<TypeOf> &);
mlir::LogicalResult convention(const Request<ConventionOf> &);
mlir::LogicalResult entry(const Request<Nothing> &);
mlir::LogicalResult linkerNames(const Request<Nothing> &);
mlir::LogicalResult loops(const Request<Loops> &);
mlir::LogicalResult straightLine(const Request<Functions> &);
mlir::LogicalResult alignedAccess(const Request<Roots> &);
mlir::LogicalResult readsNothing(const Request<Functions> &);
mlir::LogicalResult writesNothing(const Request<Functions> &);
mlir::LogicalResult solvedEffects(const Request<EffectsOf> &);
mlir::LogicalResult computesNothing(const Request<Functions> &);
mlir::LogicalResult dimsKnown(const Request<Functions> &);
mlir::LogicalResult byName(const Request<Symbol> &);
mlir::LogicalResult notByName(const Request<Symbol> &);
mlir::LogicalResult total(const Request<Functions> &);
mlir::LogicalResult notTotal(const Request<Functions> &);
mlir::LogicalResult apart(const Request<TwoFunctions> &);
mlir::LogicalResult reaches(const Request<Pair> &);
mlir::LogicalResult stage(const Request<StageIs> &);

} // namespace idr::expect

#endif // IDR_TRANSFORMS_EXPECT_H
