// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-rc: every reference made explicit, after which the program is in the
// owned stage, which the verifier holds every later pass to. It is a
// pipeline of steps (Pipeline.cpp), each a pass of its own:
//   1. idr-rc-cells, on each function: a constructor of a cell becomes the
//      cell's allocation and its initialization, so that memory is
//      explicit;
//   2. idr-rc-stack (Stack.h): a cell that never leaves its frame goes on
//      the stack, before reuse and exclusivity see it;
//   3. idr-rc-grades: the boundaries with upstream's buffer ops are marked,
//      reset/reuse and borrow inference decide on the program, and the
//      owned grades go into every signature; then, on each function, the
//      reuse rewrite at the sites the program's Reuses holds and the
//      counts, which read the grades of the function's own signature and
//      its callees' (one pass: a signature graded ahead of its callers'
//      bodies breaks their calls);
//   4. idr-rc-exclusive: exclusivity, which reads the dups placement made,
//      is solved; grade specialization copies the functions whose callers
//      disagree on a grade; the excl grades go into every signature, and
//      each function is committed, nested; every reference is then counted
//      and graded, the owned stage;
// then upstream's symbol-dce erases the copies and originals no call
// reaches any more. Steps 3 and 4 write signatures, then rewrite bodies
// while no signature changes, so a function reads only its
// own body, its own signature and its callees' signatures, and the
// functions run in parallel. Below the passes are the steps their units
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

#include <memory>

namespace idr {

#define GEN_PASS_DECL_IDRRCCELLS
#define GEN_PASS_DECL_IDRRCGRADES
#define GEN_PASS_DECL_IDRRCPLACE
#define GEN_PASS_DECL_IDRRCEXCLUSIVE
#define GEN_PASS_DECL_IDRKNOTS
#include "idr/Transforms/Passes.h.inc"

} // namespace idr

namespace mlir {
class RewriterBase;
} // namespace mlir

namespace idr::ownership {

// The commit of the excl grades `solved` proved, which idr-rc-exclusive
// runs nested on each function while it holds the solve and the program's
// `symbols`, and which counts into its `exclusive` statistic the values it
// leaves exclusive. It is no registered pass: Exclusivity is a value the
// parent made from the copies it decided, solved twice and read after the
// calls moved, which no analysis of the program can be.
std::unique_ptr<mlir::Pass> createRcCommit(const Exclusivity &solved,
                                           const mlir::SymbolTable &symbols,
                                           mlir::Pass::Statistic &exclusive);

// The owned grades borrow inference decided, written into every signature:
// an owned parameter and every result that holds references become
// `!idr.own<T>`, and the entry arguments follow.
void writeOwnedGrades(ProgramOp program, const Borrows &borrows);

// Before exclusivity's solve: a value some view of which takes a reference
// of its own gets each of its consuming uses an idr.share.
void shareTainted(ProgramOp program, const mlir::SymbolTable &symbols);

// Grade specialization's keys and copies, decided at once on what
// `solved` found of the program as placement left it. The key set comes
// first: every function some live call gives an exclusive value at each
// followed parameter while another call shares one, and every function
// such a key calls that takes a followed parameter shared, the copies' own
// callees. Then each key's copy, made once, named from the key, right
// after its original, calling what the original calls. A copy whose name
// another function holds is an internal error.
mlir::FailureOr<Copies> specializeOnGrade(ProgramOp program, const Exclusivity &solved,
                                          mlir::SymbolTable &symbols);

// Each call to where the solve of the program with its copies sent it: a
// call of a key or of its copy to the copy when it gives an exclusive value
// at every followed parameter, and to the original when it does not. The
// solve already followed every call there, so it is the solve of the
// program after the calls moved.
void redirectCalls(ProgramOp program, const Exclusivity &solved);

// The excl grades the solve proved, written into every signature and entry
// argument, and every call's results set from its callee's.
void writeExclusiveGrades(ProgramOp program, const Exclusivity &solved,
                          const mlir::SymbolTable &symbols);

// What counting does with a value, decided once for each: the placement
// it gets, not only how long it lives.
enum class Class {
  // Holds no reference counting sees: a value of a type that holds none,
  // or one whose reference a boundary with upstream's buffer ops moves.
  Untracked,
  // Stands for a value without holding a reference (poison, a small big):
  // owned by type, and never counted.
  Phantom,
  // Static data counting never frees: a view, which each consuming use
  // takes a reference of its own to (a dup that runs nothing).
  Constant,
  // Read from static data, or static data at another grade: keeps its
  // grade, and each consuming use takes a reference of its own.
  StaticRead,
  // A view of a value that is alive at each of its uses, or a parameter
  // borrow inference left a view: each consuming use takes a reference.
  Borrowed,
  // A field or an element that takes a reference of its own where it is
  // read: an idr.dup right after the read (Reshape), placed as an owned
  // value in its stead.
  OwnedAtRead,
  // Holds one reference of its own, which its last use on each path
  // consumes.
  Owned,
};

// Whether a value of `kind` holds a reference of its own once counted.
bool ownsReference(Class kind);

// The class of each value of a function as it stands, each computed once.
// A class reads where a value's uses are and where what it was read from
// is alive, so a Classes is built for one step and dropped with it: no
// class outlives a change of the code it read. A parameter that holds
// references is borrowed unless its grade, which the signature gave it, is
// owned. An element read from a buffer is owned at its read: the buffer may
// be written while a view of it would still be read. A fresh allocation and
// the value a give hands to a store are untracked: their boundary op moves
// their reference.
class Classes {
public:
  explicit Classes(FuncOp fn) : fn(fn) {}

  Class classOf(mlir::Value value);

private:
  bool aliveAt(mlir::Value value, mlir::Operation *op);

  FuncOp fn;
  llvm::DenseMap<mlir::Value, Class> classes;
};

// Whether a use of `value` is inside `region`.
bool usedIn(mlir::Value value, mlir::Region &region);

// Whether `block` ends in a crash, which counting leaves alone.
bool endsInCrash(mlir::Block &block);

// Takes the box `box`, built by the constructor `tag`, which has a cell,
// out of its cell at `at` in `block`: an idr.take whose fields replace the
// reads of the box's fields from that point on (`bound`, the arguments of
// the case region that bound them, none when no case region did, and
// idr.field).
TakeOp takeAt(mlir::RewriterBase &rewriter, mlir::Value box, Tag tag, mlir::Block &block,
              mlir::Block::iterator at, llvm::ArrayRef<mlir::BlockArgument> bound);

// Takes the scrutinee of `match` apart where its case region `index`
// begins, its fields replacing the region's arguments: out of its cell when
// the case's constructor has one, an idr.take, else an idr.unpack.
void takeAtEntry(mlir::RewriterBase &rewriter, MatchOp match, unsigned index);

// Takes the unboxed sum `value`, built by the constructor `tag`, apart
// where it is defined (idr.unpack), and gives each of its field reads the
// field taken.
void takeFields(mlir::RewriterBase &rewriter, mlir::Value value, Tag tag);

// Whether `box`, built by the constructor `tag`, keeps a field that holds
// references past `at` in `block`, where it dies.
bool keepsCountedField(mlir::Value box, Tag tag, mlir::Block &block, mlir::Block::iterator at,
                       llvm::ArrayRef<mlir::BlockArgument> bound);

// The reuse rewrite of one function: at each site, in order, the take of
// the box, and each idr.cell.new that gets its cell an idr.cell.recycle of
// the take's token.
void reuseAt(mlir::RewriterBase &rewriter, llvm::ArrayRef<Reuses::Site> sites);

// The boundaries of one function where counting meets upstream's buffer
// ops, before any analysis of idr-rc reads them: each memref.alloc's
// reference is taken over by an idr.own.adopt, and each counted
// memref.store's value handed to it by an idr.own.give. Writes nothing
// outside the function.
void boundaries(FuncOp fn);

// The counts a step of placement added to a function.
struct Counted {
  unsigned dups = 0;
  unsigned drops = 0;
};

// The code counting changes before it places a count: selects, values
// taken apart where they die, consumers moved past the reads that follow
// them, and fields and elements that take a reference of their own, the
// dups of which it gives. A call's operands take their parameters' grades
// only once placed, so what a call takes over is read from its callee's
// signature, through `symbols`.
Counted reshape(mlir::RewriterBase &rewriter, FuncOp fn, const mlir::SymbolTable &symbols);

// The counts of a function: the idr.dup, idr.drop and idr.borrow that make
// every reference consumed exactly once on every path, what a call takes
// over read through `symbols` as `reshape` reads it.
Counted place(mlir::RewriterBase &rewriter, FuncOp fn, const mlir::SymbolTable &symbols);

} // namespace idr::ownership

#endif // IDR_TRANSFORMS_OWNERSHIP_H
