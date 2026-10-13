// The one home of symbol lookup. A pass or an analysis holds a table and
// asks it, in O(1); a verifySymbolUses asks the collection it is handed. Code
// MLIR calls with no table in hand (a folder, an effect query, a range, a
// pattern) scans the nearest symbol table's top level, and only at the few
// sites that run it at most once per op they rewrite or only on ops that
// exist late: nothing is opened, published or remembered.
#ifndef IDR_IR_SYMBOLS_H
#define IDR_IR_SYMBOLS_H

#include "idr/IR/IdrDialect.h"

#include "llvm/ADT/STLFunctionalExtras.h"

#include <optional>

namespace idr {

// The declaration a !idr.data or !idr.box type names, or null for any other
// type.
mlir::FlatSymbolRefAttr getSumName(mlir::Type type);

// From the table a pass or an analysis holds: O(1).
DataOp lookupData(mlir::SymbolTable &symbols, mlir::Type type);
CtorOp lookupCtor(mlir::SymbolTable &symbols, mlir::SymbolRefAttr ctor);

// From the collection a verifySymbolUses is handed: O(1) once the
// collection has built the module's table.
DataOp lookupData(mlir::SymbolTableCollection &symbols, mlir::Operation *from, mlir::Type type);

// Within a declaration already found: the constructor `ctor` of `data`, or
// null.
CtorOp lookupCtor(DataOp data, llvm::StringRef ctor);

// A scan of the nearest symbol table's top level, for code MLIR calls with
// no table in hand, at the sites where it runs at most once per op it
// rewrites or only on ops that exist late. Nothing is opened or kept. While
// a nested manager runs no pass writes a declaration, so what it reads is
// stable on every worker.
DataOp declarationOf(mlir::Operation *from, mlir::Type type);
CtorOp constructorOf(mlir::Operation *from, mlir::SymbolRefAttr ctor);

// The cons constructor of the list `data` declares, checked against `list`
// (a box of a nil without fields and a cons of `element` and the list), or
// null with an error at `op`.
CtorOp listCons(mlir::Operation *op, DataOp data, mlir::Type list, mlir::Type element);

// Whether a value of `type` holds a reference a count accounts for;
// `declaration` finds an unboxed sum's declaration, from a table, a
// collection or a scan, as the caller has it.
bool holdsReferences(mlir::Type type, llvm::function_ref<DataOp(mlir::Type)> declaration);

// The elimination of a value that begins at one of its uses: an apply of
// the value, or of one field of it (an action in `MkIO f`), each read
// through the one use of a linear value, where the value may first pass a
// linear position entered and used at once. Each step is the one use of
// the step before, so the apply is all the use does with the value. It is
// what raising moves into a clone of a callee whose result it eliminates,
// where it meets the closure each tail builds; so a call's result that has
// one is worth moving to where the elimination is.
struct Elimination {
  // The pair that only moves the value into a linear position and out
  // again before it is read, or null.
  LinEnterOp enter;
  LinUseOp exit;
  FieldOp field; // null: the value itself is applied
  LinUseOp use;  // null: what is applied is not linear
  ApplyOp apply;
};
std::optional<Elimination> eliminationAt(mlir::OpOperand &use);

// Whether `data` is a memo sum: what idr-defunctionalize makes of a lazy
// type.
bool isMemo(DataOp data);

} // namespace idr

#endif // IDR_IR_SYMBOLS_H
