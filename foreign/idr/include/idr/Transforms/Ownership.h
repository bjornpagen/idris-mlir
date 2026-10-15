// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-rc: every reference made explicit, after which the program is in the
// owned stage, which the pass sets on it and the verifier holds every later
// pass to. The program pass decides on the program and writes signatures;
// the bodies are rewritten per function, by two passes it runs nested:
// idr-rc-place (the reuse rewrite and explicit counting) once the owned
// grades are in every signature, idr-rc-commit (the excl grades) once the
// exclusive ones are. While either runs no signature changes, so a function
// reads only its own body, its own signature and its callees' signatures,
// and the functions run in parallel. Below the pass are the steps its units
// share.
#ifndef IDR_TRANSFORMS_OWNERSHIP_H
#define IDR_TRANSFORMS_OWNERSHIP_H

#include "idr/Analysis/Ownership.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Block.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/IR/Value.h"
#include "mlir/Pass/Pass.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/MapVector.h"

#include <memory>

namespace idr {

#define GEN_PASS_DECL_IDRRC
#include "idr/Transforms/Passes.h.inc"

} // namespace idr

namespace mlir {
class RewriterBase;
} // namespace mlir

namespace idr::ownership {

// The nested passes, which idr-rc builds and no registry knows: placement,
// and the commit of the excl grades.
std::unique_ptr<mlir::Pass> createRcPlace();
std::unique_ptr<mlir::Pass> createRcCommit();

// The owned grades borrow inference decided, written into every signature:
// an owned parameter and every result that holds references become
// `!idr.own<T>`, and the entry arguments follow.
void writeOwnedGrades(ProgramOp program, const Borrows &borrows);

// Before exclusivity's solve: a value some view of which takes a reference
// of its own gets each of its consuming uses an idr.share.
void shareTainted(ProgramOp program, mlir::SymbolTable &symbols);

// The copies grade specialization made, by their original, in the order
// their keys were decided. A function has one key at most, its exclusive
// context (every followed parameter exclusive), so one copy, made once.
struct Copies {
  llvm::MapVector<mlir::Operation *, FuncOp> of;
};

// Grade specialization, decided at once on what `solved` found of the
// program as placement left it. The key set comes first: every function
// some live call gives an exclusive value at each followed parameter while
// another call shares one, and every function such a key calls that takes
// a followed parameter shared, the copies' own callees. Then each key's
// copy, made once, named from the key, right after its original; then
// every such call goes to its callee's copy, and every call a copy makes
// to a key goes to that key's copy, so the copies call one another as the
// originals do. A copy whose name another function holds is an internal
// error.
mlir::FailureOr<Copies> specializeOnGrade(ProgramOp program, const Exclusivity &solved,
                                          mlir::SymbolTable &symbols);

// On the solve of the program the copies are in: each live call of a key
// or of its copy goes to the copy when it gives an exclusive value at every
// followed parameter, and to the original when it does not, so that it
// shares no copy's parameters. Whether any call moved, after which the
// program is solved once more.
bool redirectCalls(ProgramOp program, const Exclusivity &solved, mlir::SymbolTable &symbols,
                   const Copies &copies);

// Every copy and every original that nothing calls any more, once the
// calls went where they go.
void eraseUnused(ProgramOp program, mlir::SymbolTable &symbols, const Copies &copies);

// The excl grades the solve proved, written into every signature and entry
// argument, and every call's results set from its callee's.
void writeExclusiveGrades(ProgramOp program, const Exclusivity &solved,
                          mlir::SymbolTable &symbols);

// The class of a value, as counting places it.
enum class Class { Untracked, Static, Borrowed, Owned };

// The class of each value of a function, computed once. A parameter that
// holds references is borrowed unless its grade, which the signature gave
// it, is owned. An element read from a buffer is owned: it takes a
// reference of its own where it is read. A fresh allocation and the value
// a give hands to a store are untracked: their boundary op moves their
// reference.
class Classes {
public:
  explicit Classes(FuncOp fn) : fn(fn) {}

  Class classOf(mlir::Value value);

  // Forgets the class of `value`, whose definition changed.
  void erase(mlir::Value value) { classes.erase(value); }

private:
  bool aliveAt(mlir::Value value, mlir::Operation *op);

  FuncOp fn;
  llvm::DenseMap<mlir::Value, Class> classes;
};

// Whether a use of `value` is inside `region`.
bool usedIn(mlir::Value value, mlir::Region &region);

// Whether `block` ends in a crash, which counting leaves alone.
bool endsInCrash(mlir::Block &block);

// Takes the box `box`, built by the constructor `tag` of `data`, apart at
// `at` in `block`: an idr.take whose fields replace the reads of the box's
// fields from that point on (the arguments of `fields`, the case region
// that bound them, when one did, and idr.field).
TakeOp takeAt(mlir::RewriterBase &rewriter, mlir::Value box, DataType data, unsigned tag,
              mlir::Block &block, mlir::Block::iterator at, mlir::Block *fields);

// Takes the scrutinee of `match` apart where its case region `index`
// begins: an idr.take whose fields replace the region's arguments.
TakeOp takeAtEntry(mlir::RewriterBase &rewriter, MatchOp match, unsigned index);

// Takes the unboxed sum `value`, built by the constructor `tag` whose
// fields have `fieldTypes`, apart where it is defined, and gives each of
// its field reads the field taken.
TakeOp takeFields(mlir::RewriterBase &rewriter, mlir::Value value, unsigned tag,
                  llvm::ArrayRef<mlir::Type> fieldTypes);

// Whether `box`, built by the constructor `tag`, keeps a field that holds
// references past `at` in `block`, where it dies.
bool keepsCountedField(mlir::Value box, unsigned tag, mlir::Block &block,
                       mlir::Block::iterator at, mlir::Block *fields);

// The reuse rewrite of one function: at each site, in order, the take and
// the reuses of its cell.
void reuseAt(mlir::RewriterBase &rewriter, llvm::ArrayRef<Reuses::Site> sites);

// The buffers of one function in the form counting counts, before any
// analysis of idr-rc reads them: a loop whose payload takes or yields an
// element that holds references becomes its scf.for loops, whose loads and
// stores counting grades, and a load of a counted element nothing reads is
// no read at all; each memref.alloc's reference is taken over by an
// idr.own.adopt, and each counted memref.store's value handed to it by an
// idr.own.give. Writes nothing outside the function.
mlir::LogicalResult bufferForms(FuncOp fn);

// The code counting changes before it places a count, after it checked it
// can count the function: selects, values taken apart where they die,
// consumers moved past the reads that follow them, and fields and elements
// that take a reference of their own.
mlir::LogicalResult reshape(mlir::RewriterBase &rewriter, FuncOp fn, Classes &classes,
                            mlir::SymbolTable &symbols);

// The counts of a function: the idr.dup, idr.drop and idr.borrow that make
// every reference consumed exactly once on every path.
void place(mlir::RewriterBase &rewriter, FuncOp fn, Classes &classes, mlir::SymbolTable &symbols);

} // namespace idr::ownership

#endif // IDR_TRANSFORMS_OWNERSHIP_H
