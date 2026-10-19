// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The arguments of idr-expect's properties: the shapes a request's argument
// may have, each the typed value its text is read into once, before the
// check runs, by the one parser of the shape (Arguments.cpp, Values.cpp).
// A text that does not have the shape is refused there, in the one wording
// every property shares, and an `@f` that names no function is refused
// there too; a check takes the typed value and never reads text.
#ifndef IDR_TRANSFORMS_EXPECTARGUMENTS_H
#define IDR_TRANSFORMS_EXPECTARGUMENTS_H

#include "idr/IR/IdrDialect.h"

#include "mlir/Dialect/LLVMIR/LLVMAttrs.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/OwningOpRef.h"
#include "mlir/Interfaces/FunctionInterfaces.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"

#include <cstdint>
#include <optional>
#include <string>
#include <variant>

namespace idr::expect {

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

// `<v><separator><v>...`: each item, read (Values.cpp), for every shape
// that holds a list of values.
mlir::FailureOr<llvm::SmallVector<Item>> valuesOf(const Written &written, llvm::StringRef text,
                                                  char separator);

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

} // namespace idr::expect

#endif // IDR_TRANSFORMS_EXPECTARGUMENTS_H
