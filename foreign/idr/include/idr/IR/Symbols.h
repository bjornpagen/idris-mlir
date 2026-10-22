// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a value's type says of its data beyond the type's own accessors,
// read from the type, never from the module; a constructor written by its
// label; the elimination of a value at one of its uses; the digest of an
// attribute's or a type's content, which copies are named by; and the
// names the lowering reserves for itself.
#ifndef IDR_IR_SYMBOLS_H
#define IDR_IR_SYMBOLS_H

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/OpImplementation.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/Support/xxhash.h"

#include <optional>
#include <string>
#include <utility>

namespace idr {

// The data type a value of `type` is of, through its grade; null for any
// other type.
DataType dataTypeOf(mlir::Type type);

// Whether how `value` was built (its idr.data.con, its constant) still says
// its constructor where `reader` reads it. Always, but for a memo cell,
// whose state every force writes: never for a constant, one static cell
// every run of the program shares and forces, and for a cell an
// idr.data.con built only while nothing but `reader` runs its force
// (idr.memo.run).
bool builtStateHolds(mlir::Value value, mlir::Operation *reader);

// A constructor written by its label, `@Name`, in the family of `type` (a
// data type at any grade), and read back into its tag, an i32 attribute:
// the one place a constructor's label becomes its tag outside a type's own
// syntax. An op's assembly format reads one as
// `custom<CtorRef>(ref(type($x)), $tag)`, after the type that names it.
mlir::ParseResult parseCtorRef(mlir::AsmParser &parser, mlir::Type type, mlir::IntegerAttr &tag);
void printCtorRef(mlir::OpAsmPrinter &printer, mlir::Operation *op, mlir::Type type,
                  mlir::IntegerAttr tag);

// The elimination of a value that begins at one of its uses: the dispatch
// on the value, or on one field of it (an action in `MkIO f`), each read
// through the one use of a linear value, where the value may first pass a
// linear position entered and left at once. Each step is the one use of
// the step before, so the dispatch is all the use does with the value. The
// dispatch is the first op that eliminates the value: for a closure sum,
// an idr.data.match of the sum or an idr.data.field of it; for a string,
// its output (idr.io.put_str). A field of a value of any other family is a
// step. It is what raising moves into a clone of a callee whose result it
// eliminates, where it meets the closure or the string each tail builds.
struct Elimination {
  // The pair that only moves the value into a linear position and out
  // again before it is read, when there is one.
  std::optional<std::pair<LinCastOp, LinCastOp>> passed;
  // The field dispatched on, when it is not the value itself.
  std::optional<DataFieldOp> field;
  // The one use of what is dispatched on, when it is linear.
  std::optional<LinCastOp> use;
  // An idr.data.match or idr.data.field of a closure sum, or an
  // idr.io.put_str of a string, its operand the last step's result.
  mlir::Operation *dispatch;

  // The ops from the use to the dispatch, each the one use of the one
  // before, in the order they run.
  llvm::SmallVector<mlir::Operation *> steps() const;
};
std::optional<Elimination> eliminationAt(mlir::OpOperand &use);

// XXH3-128 of an attribute's or a type's content, the same in every
// process: what its dialect's bytecode writes of it, each attribute or
// type it holds written as that one's own digest, so no address, TypeID or
// printing flag reaches it. A name made of it (a specialized copy's, a
// deduplicated function's) is the same however the module was built.
llvm::XXH128_hash_t stableDigest(mlir::Attribute attr);
llvm::XXH128_hash_t stableDigest(mlir::Type type);

// A symbol the lowering makes for itself, outside the program's names:
// `__idr$<kind>$<discriminator>`, `kind` a word that starts with a letter.
// It is never a program symbol's mangling (conversion::mangle): a mangled
// name's first `$` opens an escape, so a digit follows it, where a letter
// follows a reserved name's first `$`. It is never a runtime function's
// name either, a C identifier, which holds no `$`. So a reserved name is
// distinct by its spelling, and no check of a collision guards it.
std::string reservedName(llvm::StringRef kind, llvm::StringRef discriminator);

} // namespace idr

#endif // IDR_IR_SYMBOLS_H
