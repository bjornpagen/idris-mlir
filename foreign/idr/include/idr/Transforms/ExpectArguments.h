// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The arguments of idr-expect's properties: the shapes a request's argument
// may have, each the typed value its text is read into once, before the
// check runs, by the one parser of the shape (Arguments.cpp). The table of
// properties (harness/Properties.idr) names each property's shape.
// A text that does not have the shape is refused there, in the one wording
// every property shares, and an `@f` that names no function is refused
// there too; a check takes the typed value and never reads text.
#ifndef IDR_TRANSFORMS_EXPECTARGUMENTS_H
#define IDR_TRANSFORMS_EXPECTARGUMENTS_H

#include "mlir/IR/BuiltinOps.h"
#include "mlir/Interfaces/FunctionInterfaces.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"

#include <optional>
#include <string>

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

} // namespace idr::expect

#endif // IDR_TRANSFORMS_EXPECTARGUMENTS_H
