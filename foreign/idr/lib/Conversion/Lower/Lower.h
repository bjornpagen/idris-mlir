// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What the steps of idr-lower share, inside the lowering: the functions as
// LLVM's (phase 0), what LLVM is told of a row, the rules of a lifetime's
// kind, and the preparation of a function's lifetimes before its ops are
// converted (phase 1).
#ifndef IDR_LIB_CONVERSION_LOWER_LOWER_H
#define IDR_LIB_CONVERSION_LOWER_LOWER_H

#include "idr/IR/Effects/LLVM.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Lifetimes.h"
#include "idr/Conversion/Runtime.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Transforms/DialectConversion.h"
#include "llvm/ADT/SmallVector.h"

namespace idr::conversion {

//===----------------------------------------------------------------------===//
// What LLVM is told
//===----------------------------------------------------------------------===//

// A function's facts, as the effect system tells them of its row and its
// record (rows::told): `memory`, `will_return`, `no_unwind`, and
// `mustprogress`, `nofree` and `nosync` among its passthrough attributes,
// each told unless an atom withholds it.
void tellFunction(mlir::LLVM::LLVMFuncOp fn, const effects::Told &told);

// A call's facts from the row it carries, made once where the row is a
// constant of the op's class: what a call says itself, since linking the
// runtime replaces a declaration's attributes by the definition's.
struct CallFacts {
  mlir::LLVM::MemoryEffectsAttr memory;
  effects::Told told;
};
CallFacts callFacts(mlir::MLIRContext *ctx, effects::Row row);
void tellCall(mlir::LLVM::CallOp call, const CallFacts &facts);

//===----------------------------------------------------------------------===//
// Cells
//===----------------------------------------------------------------------===//

// The constructor a data type refined to one constructor names.
inline Tag tagOf(DataType data) { return data.possibleTags().front(); }

// The layout of a cell of `type`: its family's cell of the constructor the
// cell is for, both of which the cell's type says.
inline const layout::Cell &cellLayoutOf(const Layouts &layouts, CellType type) {
  return layouts.cells(type.getData()).cell(type.getTag());
}

//===----------------------------------------------------------------------===//
// Regions run once
//===----------------------------------------------------------------------===//

// `op`'s results converted, each to its components: what an op lowered to
// an scf op gives, flattened in order, and how they group back.
mlir::FailureOr<llvm::SmallVector<llvm::SmallVector<mlir::Type>>>
convertedResults(mlir::Operation *op, const mlir::TypeConverter &converter);

// `from`, a region of one block that ends in an idr.yield or never ends,
// moved to the end of `into`, an scf op's region, its block's arguments
// replaced by `args` (one range per argument, empty for an argument with no
// run-time value) and its idr.yield made scf's. Blocks then appear only
// where upstream's scf patterns make them.
void moveRegion(mlir::ConversionPatternRewriter &rewriter, const mlir::TypeConverter &converter,
                mlir::Region &from, llvm::ArrayRef<llvm::SmallVector<mlir::Value>> args,
                mlir::Region &into);

// The values an scf op gives for an op's results, grouped back by
// `converted`.
llvm::SmallVector<llvm::SmallVector<mlir::Value>>
groupResults(mlir::ValueRange flat, llvm::ArrayRef<llvm::SmallVector<mlir::Type>> converted);

//===----------------------------------------------------------------------===//
// Lifetimes
//===----------------------------------------------------------------------===//

// What a lifetime's kind lowers to, one context-free rule per kind, so the
// converter caches it: a view and a home to no value, dropped from every
// signature, call and frame; a room to the pointer to its block; a cursor
// to a pointer, the cursor at a function's boundary and the address of its
// slot inside the function.
void addLifetimeConversions(mlir::TypeConverter &converter);

// A function's lifetimes made ready, still on idr types and before any
// signature changes: each cursor parameter's value kept in a slot of the
// frame, which every use reads and every return gives back; each room's
// block laid out once, in program order, every put into it (a cell, or a
// call taking its callee's bound) at its offset, and each block opener's
// block allocated in the frame. `program` resolves a callee's bound and is
// read only, so every function is made ready at once. Fails, having
// reported it, where a callee bounds no room it is given: an internal
// error, since a room is a block of static size.
mlir::LogicalResult prepareLifetimes(FuncOp fn, const mlir::SymbolTable &program,
                                     const Layouts &layouts);

//===----------------------------------------------------------------------===//
// Functions
//===----------------------------------------------------------------------===//

// The LLVM type of a function of idr type `type`: each parameter's
// components, and one result, void, a component, or a literal struct of
// the results' components followed by each cursor parameter's cursor.
mlir::LLVM::LLVMFunctionType functionType(mlir::FunctionType type,
                                          const mlir::TypeConverter &converter);

// Each call that gives a lifetime of another kind where its callee asks a
// view gives that view, on the program, serially, before anything reads a
// call's lifetimes.
void viewsWhereAsked(ProgramOp program);

// Phase 0, on the program, serially: every function's name takes the
// program's prefix at every use; then every idr.func becomes, where it is,
// the llvm.func of its mangled name and lowered type, its body moved whole,
// under `tailcc`, private, with what its row and record tell LLVM and the
// facts of each parameter's components. Gives the functions, in program
// order.
llvm::SmallVector<mlir::LLVM::LLVMFuncOp> lowerSignatures(ProgramOp program,
                                                          const mlir::TypeConverter &converter,
                                                          const Layouts &layouts);

// The patterns of phase 2 that take a function's own ops out of idr: its
// entry block's arguments, its calls (a call in tail position musttail,
// every call of the program under tailcc) and its returns.
void populateFunctionPatterns(mlir::RewritePatternSet &patterns,
                              const mlir::TypeConverter &converter, const Layouts &layouts,
                              Runtime &runtime);

// The patterns of the lifetimes' ops: the openers, this activation's
// lifetime, the loan, the derived lifetimes, the cells put into one, and
// the pack and unpack that split a lifetime around a framed call.
void populateLifetimePatterns(mlir::RewritePatternSet &patterns,
                              const mlir::TypeConverter &converter, const Layouts &layouts,
                              Runtime &runtime);

} // namespace idr::conversion

#endif // IDR_LIB_CONVERSION_LOWER_LOWER_H
