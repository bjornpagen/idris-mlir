// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What the steps of idr-lower share, inside the lowering: the functions as
// LLVM's (phase 0), what LLVM is told of a row, how a cell is read and a
// value dropped, what is made ready of a function before its ops are
// converted (its lifetimes and its account), and a value re-packed from
// one layout into another.
#ifndef IDR_CONVERSION_LOWER_LOWER_H
#define IDR_CONVERSION_LOWER_LOWER_H

#include "idr/IR/Effects/LLVM.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Lifetimes.h"
#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/Conversion/Runtime.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Rewrite/FrozenRewritePatternSet.h"
#include "mlir/Transforms/DialectConversion.h"
#include "llvm/ADT/SmallVector.h"

#include <cstdint>

namespace idr::conversion {

//===----------------------------------------------------------------------===//
// What LLVM is told
//===----------------------------------------------------------------------===//

// A function's facts, as the effect system tells them of its row and its
// record (rows::told): `memory`, `will_return`, `no_unwind`, and every
// other function attribute among its passthrough attributes, each told
// unless an atom withholds it.
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

// What a load of a cell of `data` reads: a data cell is immutable until its
// memory is reused, which launders the pointer; a memo cell's state and
// fields change when it is forced, and a frame's memory is the next push's.
inline Contents contentsOf(DataType data) {
  return data.memo() || data.layout() == Layout::FrameStack ? Contents::MayChange
                                                             : Contents::Stays;
}

// A drop of a value of `type`, its components `value`: where its type claims
// its own cells unshared and it has some, a data type in a cell or in place,
// those cells freed with no count read and what the claim says nothing of
// dropped by its counts; otherwise one reference less to each counted word,
// a cell freed at 0.
void dropValue(mlir::OpBuilder &b, mlir::Location loc, const Runtime &runtime,
               const Layouts &layouts, mlir::Type type, mlir::ValueRange value);

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

// A function's lifetimes made ready, still on idr types and before any
// signature changes: each cursor parameter's value kept in a slot of the
// frame, which every use reads and every return gives back; each room's
// block laid out once, in program order, every put into it (a cell, or a
// call taking its callee's bound) at its offset, and each block opener's
// block allocated in the frame. `graph` resolves a callee's bound and is
// read only, so every function is made ready at once. Fails, having
// reported it, where a callee bounds no room it is given: an internal
// error, since a room is a block of static size.
mlir::LogicalResult prepareLifetimes(FuncOp fn, const solver::ProgramGraph &graph,
                                     const Layouts &layouts);

// The patterns that tell a call's account, in the checked runtime, where
// the call ends: at a return or before a call in tail position.
mlir::FrozenRewritePatternSet accountPatterns(mlir::MLIRContext *ctx, const Runtime &runtime);

// A function's account made ready, still on idr types, before its
// lifetimes are made ready and before any signature changes: where
// its frame bound is not zero, opened at its entry with the bound, told
// each point where what it holds dead rises or falls (counting's hold
// points, the walk its bound rests on) and told where it ends by `tells`;
// nothing where its bound is zero.
void keepAccount(FuncOp fn, const mlir::FrozenRewritePatternSet &tells, const Layouts &layouts,
                 const Runtime &runtime);

//===----------------------------------------------------------------------===//
// Re-packs
//===----------------------------------------------------------------------===//

// How a re-pack gives up a cell it takes apart: the value holds one
// reference to it among others (each field gains one, the cell loses one),
// holds it alone (its memory given back, its fields moving out), or frees
// nothing (it is read where its owner keeps it, or it is scoped or static).
enum class Taken : std::uint8_t { Shared, Alone, Borrowed };

// How a value's own cell is taken, and every cell its fields reach.
struct Takes {
  Taken own;
  Taken reached;
};

// A value given on whole, as its grade holds it: a claim on its own cells
// reaches its first cell, a deep claim every cell.
Takes takesOf(mlir::Type type);

// A value read where its owner keeps it.
inline constexpr Takes readInPlace{Taken::Borrowed, Taken::Borrowed};

// `values`, a value of type `from`, as a value of type `to`, two types of
// one value: a reindex's operand and result, or a field's type at its
// value's application and the type its slot is laid out at. The same words
// where the two lay out alike. Otherwise re-packed: a numeral made a
// natural or made of one, an array copied element by element into a fresh
// array, and any other value taken apart at each constructor both types
// leave possible and built again, its fields re-packed in turn, a cell
// allocated as every counted cell is and an atom the static cell of its
// constructor. A cell taken apart is given up as `takes` says; a re-pack
// that builds a cell or an array gives a fresh value, which holds what it
// holds on its own whatever `takes` says.
llvm::SmallVector<mlir::Value> repack(mlir::OpBuilder &b, mlir::Location loc,
                                      const Layouts &layouts, Runtime &runtime, mlir::Type from,
                                      mlir::Type to, mlir::ValueRange values, Takes takes);

// Each field `operands` gives constructor `tag` of `data`, its components
// `given`, re-packed from its own type into the type its slot is laid out
// at, each given on whole.
llvm::SmallVector<llvm::SmallVector<mlir::Value>>
intoSlots(mlir::OpBuilder &b, mlir::Location loc, const Layouts &layouts, Runtime &runtime,
          DataType data, Tag tag, mlir::ValueRange operands,
          llvm::ArrayRef<mlir::ValueRange> given);

// The patterns of the values of ours that are no cell: a constant, poison,
// a select, and the region in which an assumed equality holds.
void populateValuePatterns(mlir::RewritePatternSet &patterns,
                           const mlir::TypeConverter &converter, const Layouts &layouts,
                           Runtime &runtime);

// The pattern of idr.data.reindex: its operand's words where the op is
// free, else its operand re-packed into its result's layout.
void populateReindexPatterns(mlir::RewritePatternSet &patterns,
                             const mlir::TypeConverter &converter, const Layouts &layouts,
                             Runtime &runtime);

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
// call's lifetimes; `graph` resolves each callee.
void viewsWhereAsked(ProgramOp program, const solver::ProgramGraph &graph);

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
// lifetime, the loan for a region, the derived lifetimes and the cells put
// into one.
void populateLifetimePatterns(mlir::RewritePatternSet &patterns,
                              const mlir::TypeConverter &converter, const Layouts &layouts,
                              Runtime &runtime);

// The patterns of the pack and the unpack that split a lifetime around a
// framed call.
void populatePackagePatterns(mlir::RewritePatternSet &patterns,
                             const mlir::TypeConverter &converter, const Layouts &layouts,
                             Runtime &runtime);

} // namespace idr::conversion

#endif // IDR_CONVERSION_LOWER_LOWER_H
