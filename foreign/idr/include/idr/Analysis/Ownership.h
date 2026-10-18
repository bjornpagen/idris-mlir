// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What idr-rc decides before it rewrites anything: which parameters are
// borrowed (Borrows), where each function's dead boxes are taken apart and
// which constructors get their cells (Reuses), and which owned values hold
// the only reference to every cell they reach (Exclusivity); and the
// vocabulary of placement those analyses and idr-rc's passes share: where a
// value is used, where it dies, and which values hold references.
//
// A value holds references when its type says so (ValueFactsTypeInterface:
// a string, a big, a box, a buffer, a reuse token, or an unboxed sum with a
// slot of one of these). In the owned stage its grade says what it holds:
//   - owned (`!idr.own<T>`): one reference of its own, which exactly one
//     use on every path consumes. Results of calls, constructors,
//     primitives, matches and loops are owned, and so are the parameters
//     that borrow inference leaves owned;
//   - a view (the view grade, `view(T)`; a buffer's view and static data
//     stay plain): none; it lives as long as what it was read from. A
//     borrowed parameter lives as long as the call, a field of a
//     constructor (an idr.field, or a field a match region binds), a view
//     of a buffer (a subview, a cast, a reshape) and an idr.borrow as long
//     as the value it was read from, and static data (a constant, whose
//     cells no count reaches) forever. An element read from a buffer is
//     never left a view: the buffer may be written while the view is read.
// idr.dup gives a view one reference of its own, which one use consumes.
//
// Reuses and Borrows are analyses the program's analysis manager caches,
// which idr-rc's steps read; Exclusivity is a value its solve returns, as
// it is solved twice over the copies grade specialization makes. Each is
// read-only once built, so the function passes of idr-rc may read it from
// any thread.
#ifndef IDR_ANALYSIS_OWNERSHIP_H
#define IDR_ANALYSIS_OWNERSHIP_H

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Block.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/IR/Value.h"
#include "mlir/Pass/AnalysisManager.h"
#include "mlir/Support/LLVM.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseMapInfoVariant.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/MapVector.h"
#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <cstdint>
#include <optional>
#include <variant>

namespace idr::ownership {

// A point between two ops of a block: its start, or right after an op. A
// point names the op before it, not the one after: what a rewrite puts at
// the point goes there whatever comes to stand after it. A point is a key
// of LLVM's hashed containers.
struct BlockStart {
  mlir::Block *block;
  bool operator==(const BlockStart &) const = default;
};
struct After {
  mlir::Operation *op;
  bool operator==(const After &) const = default;
};
using Point = std::variant<BlockStart, After>;

// The block of `point`, and its first op at or after the point.
mlir::Block &blockOf(const Point &point);
mlir::Block::iterator firstAt(const Point &point);
// The point right before `at` in `block`.
Point pointBefore(mlir::Block &block, mlir::Block::iterator at);
// The point where `value` is defined: the start of its block for a block
// argument, right after its op for a result.
Point definedAt(mlir::Value value);

// The op of `block` that holds `use`, when that op is at `from` or after
// it; null when the use is not in the block or is before `from`. The one
// walk of a use up to the block that holds it.
mlir::Operation *heldIn(mlir::Block &block, mlir::OpOperand &use, mlir::Block::iterator from);

// The ops of `block` from `from` on that use `value`, themselves or in
// their regions, in order. The second form takes the uses as a caller sees
// them, which may be fewer than the value's own.
llvm::SmallVector<mlir::Operation *> usersIn(mlir::Value value, mlir::Block &block,
                                             mlir::Block::iterator from);
llvm::SmallVector<mlir::Operation *> usersIn(llvm::ArrayRef<mlir::OpOperand *> uses,
                                             mlir::Block &block, mlir::Block::iterator from);

// Whether each run of `op` enters exactly one of its regions, once, and
// leaves it back to `op`, as RegionBranchOpInterface says: a match, an
// scf.if with both branches, an scf.index_switch. Counting moves a value
// from outside into each such region, which consumes or drops it there.
// Any other op with regions may run one many times or none (a loop, a
// branch with no else, a structured op on buffers): it holds a value from
// outside for as long as it runs, and its regions only read it.
bool decides(mlir::Operation *op);

// Whether `value` is used after `op`, where the reference it holds must
// still be there: later in the block of `op`, or after an op that holds
// that block, up to the block that defines it; and anywhere inside an op
// that does not decide (a loop) and uses the value inside, which holds it
// for as long as it runs. A use of a view of the value is not a use of it:
// whether the value outlives the view is what the caller asks.
bool usedAfter(mlir::Value value, mlir::Operation *op);

// Where a value whose uses are `uses`, which `block` holds a reference to,
// dies on each path of the block: at its start when nothing there uses it,
// after its last use, or inside each region of that use when it decides.
// Nowhere on a path whose last use takes it over (`takesOver`, the
// caller's rule, which is what the program's grades let it know: before
// borrow inference grades the signatures, any call may take its arguments
// over). Calls `at` with each point.
void whereDies(llvm::ArrayRef<mlir::OpOperand *> uses, mlir::Block &block,
               llvm::function_ref<bool(mlir::OpOperand &)> takesOver,
               llvm::function_ref<void(mlir::Block &, mlir::Block::iterator)> at);
void whereDies(mlir::Value value, mlir::Block &block,
               llvm::function_ref<bool(mlir::OpOperand &)> takesOver,
               llvm::function_ref<void(mlir::Block &, mlir::Block::iterator)> at);

// A field of a box as its uses read it, at its index in the constructor.
struct Field {
  mlir::Value value;
  unsigned index;
};

// The fields of a box whose uses are `uses`, built by the constructor
// `tag`, that a take of it gives: the arguments `bound` of the case region
// that bound them (none when no case region did) and the results of the
// idr.field reads of the box.
llvm::SmallVector<Field> fieldsOf(llvm::ArrayRef<mlir::OpOperand *> uses, Tag tag,
                                  llvm::ArrayRef<mlir::BlockArgument> bound);

// The first read of a box that no match takes apart and whose every use
// reads a field of one constructor, the point from which the box's
// constructor is known in that read's block; null for any other value. The
// second form asks of a value of `type` whose uses are `uses`.
FieldOp onlyReads(mlir::Value box);
FieldOp onlyReads(mlir::Type type, llvm::ArrayRef<mlir::OpOperand *> uses);

// The values whose cell graph exclusivity follows: owned boxes and unboxed
// sums (whose slots may hold boxes), the tokens of their cells, and the
// cells themselves, which have no grade: a box built in a cell is new to
// anyone exactly when its cell is.
bool followed(mlir::Value value);

// Whether `value` holds references: its type does (holdsReferences), and
// it is not static.
bool tracked(mlir::Value value);

// Whether a value of `type` is a memo cell, the box of a memo sum: the one
// cell that changes while references to it live, as a force writes its
// state. So its constructor is not known under a match on it, and it is
// never taken apart or built in; and no function takes one over, so the
// dispatch that writes it reads a view of its caller's.
bool isMemoCell(mlir::Type type);

// Whether `value` is an element read from a buffer that holds references.
// It takes a reference of its own where it is read: the buffer may be
// written while a view of the element would still be read, which a field
// of a cell never is. So it is never a view, and the buffer it was read
// from needs nothing for it.
bool isCountedElement(mlir::Value value);

// The copies grade specialization made: each key, a function some live
// call gives an exclusive value at every followed parameter while another
// call shares one (or one such a key calls), and its copy, which takes
// every followed parameter exclusive, in the order the keys were decided.
struct Copies {
  llvm::MapVector<FuncOp, FuncOp> of;
};

} // namespace idr::ownership

template <> struct llvm::DenseMapInfo<idr::ownership::BlockStart> {
  static unsigned getHashValue(const idr::ownership::BlockStart &at) {
    return DenseMapInfo<mlir::Block *>::getHashValue(at.block);
  }
  static bool isEqual(const idr::ownership::BlockStart &a, const idr::ownership::BlockStart &b) {
    return a == b;
  }
};

template <> struct llvm::DenseMapInfo<idr::ownership::After> {
  static unsigned getHashValue(const idr::ownership::After &at) {
    return DenseMapInfo<mlir::Operation *>::getHashValue(at.op);
  }
  static bool isEqual(const idr::ownership::After &a, const idr::ownership::After &b) {
    return a == b;
  }
};

namespace idr {

// Reset/reuse insertion's decisions: in each function, the dead boxes that
// are taken apart where they die and the heap cells made after each that
// recycle its cell. Each function's sites depend on its body, the data
// types and the layouts alone.
class Reuses {
public:
  // A field an earlier site's take gave, by the site's position among the
  // function's sites: a take before this one gave the box's reads a field
  // of its own, which is what this one takes apart.
  struct TakenField {
    unsigned site;
    unsigned field;
    bool operator==(const TakenField &) const = default;
  };

  // A take and the cells that recycle its cell. The take goes at `point`;
  // `bound` are the fields of the case region that bound the box's fields,
  // none when no case region did. The box is a value of the function, or a
  // field of an earlier take. It was built by the constructor `tag` of
  // `data`. Each of `cells` is an idr.cell.new idr-rc's place step
  // replaces by an idr.cell.recycle of the take's token.
  struct Site {
    std::variant<mlir::Value, TakenField> box;
    DataType data;
    Tag tag;
    ownership::Point point;
    llvm::SmallVector<mlir::BlockArgument> bound;
    llvm::SmallVector<CellNewOp> cells;
  };

  // The sites of every function of `program`, on the layouts the target
  // gives.
  Reuses(mlir::Operation *program, mlir::AnalysisManager &am);

  // The sites of `fn`, a function of the program, in the order they are
  // rewritten.
  llvm::ArrayRef<Site> sites(FuncOp fn) const { return sitesOf.find(fn)->second; }

private:
  llvm::DenseMap<FuncOp, llvm::SmallVector<Site>> sitesOf;
};

// Borrow inference: which parameters of the program's functions are
// borrowed, a view of the caller's value, and which are owned. A parameter
// that a reuse site takes apart is owned, so it reads the reuses decided.
class Borrows {
public:
  enum class Param : uint8_t { Untracked, Borrowed, Owned };

  // The inference over `program`, from the reuses decided, the program's
  // cycles of calls and its symbols, each cached beside it.
  Borrows(mlir::Operation *program, mlir::AnalysisManager &am);

  // Each parameter of `fn`, a function of the program.
  llvm::ArrayRef<Param> params(FuncOp fn) const { return paramsOf.find(fn)->second; }
  // How many parameters that hold references are borrowed.
  unsigned borrowed() const { return numBorrowed; }

private:
  llvm::DenseMap<FuncOp, llvm::SmallVector<Param>> paramsOf;
  unsigned numBorrowed = 0;
};

// Exclusivity, solved on MLIR's solver and kept as tables: which owned
// values hold the only reference to every cell their cell graph reaches
// that a take could hand out, which blocks run, where each call of a key
// of grade specialization goes, who calls each function and what each
// returns from. No solver outlives the solve.
class Exclusivity {
public:
  // What is known of a value's cell graph: nothing yet (the optimistic
  // start), a tree of cells this value alone reaches, or cells another
  // reference may reach.
  enum class Sharing : uint8_t { Unknown, Exclusive, Shared };

  // One solve of `program`. A call of a key of `copies` or of its copy
  // goes, within the solve, to the copy when it gives an exclusive value at
  // every followed parameter, and to the original when it does not; so the
  // copy's followed parameters are exclusive, a call that gives exclusive
  // values only once other calls went to the copies is followed in the
  // same solve, and the solve is the one of the program after each such
  // call went where it found it goes. With no copies every call goes to
  // its callee. Failure when MLIR's solver fails, an internal error the
  // caller reports.
  static mlir::FailureOr<Exclusivity> solve(ProgramOp program, const ownership::Copies &copies);

  // What the solve found of `value`; Unknown for a value it never reached.
  Sharing of(mlir::Value value) const;
  // Whether the grade excl goes on `value`: it is followed, exclusive, and
  // no share forgot that; a change of quantity follows its operand.
  bool proves(mlir::Value value) const;
  // Whether the solve found that `block` may run.
  bool live(mlir::Block *block) const { return liveBlocks.contains(block); }
  // Where the solve sent `call`, a live call of a key of the copies it was
  // given or of its copy: the copy or the original. None for any other
  // call.
  std::optional<FuncOp> target(CallOp call) const;
  // The calls the solve sent to `fn`, from the blocks that run of the
  // functions that run; none exactly when the solve does not see every
  // call of it (its callers are not all the program's).
  std::optional<llvm::ArrayRef<CallOp>> callers(FuncOp fn) const;
  // The returns of `fn` the solve reached, when a call that runs goes to
  // it; empty when none does. Every function of the program has its entry.
  llvm::ArrayRef<ReturnOp> returns(FuncOp fn) const { return returnsOf.at(fn); }

private:
  Exclusivity() = default;

  llvm::DenseMap<mlir::Value, Sharing> sharing;
  llvm::DenseSet<mlir::Block *> liveBlocks;
  llvm::DenseMap<mlir::Operation *, FuncOp> targets;
  llvm::DenseMap<FuncOp, llvm::SmallVector<CallOp>> callersOf;
  llvm::DenseMap<FuncOp, llvm::SmallVector<ReturnOp>> returnsOf;
};

} // namespace idr

// A taken field is a key of Reuses' tables, as a point is of idr-rc's.
template <> struct llvm::DenseMapInfo<idr::Reuses::TakenField> {
  static unsigned getHashValue(const idr::Reuses::TakenField &field) {
    return DenseMapInfo<std::pair<unsigned, unsigned>>::getHashValue({field.site, field.field});
  }
  static bool isEqual(const idr::Reuses::TakenField &a, const idr::Reuses::TakenField &b) {
    return a == b;
  }
};

#endif // IDR_ANALYSIS_OWNERSHIP_H
