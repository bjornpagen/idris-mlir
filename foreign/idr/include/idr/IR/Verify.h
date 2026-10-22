// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The verifier of a program, at the stage its idr.program says: the
// program's rules (its data types, its effects and the cells its recycles
// give), which idr.program's region verifier runs once it has checked the
// root and every op of the program is verified, on one thread, when the
// module is read and after every pass on the program; and the rules of one
// function at its program's stage, which idr.func's region verifier runs
// after its body's ops are, in parallel with every other function's. A
// function's rules read the function, the types its values have and its
// program's stage, and nothing else of the module, so no pass rewriting a
// sibling function races them; nothing keeps a table or an answer beyond
// one verify. The knot rule is no verifier's: it refuses the user's program,
// so it is the body of a check pass (knots).
#ifndef IDR_IR_VERIFY_H
#define IDR_IR_VERIFY_H

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/Operation.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Support/LLVM.h"

namespace idr {

class TypeGraph;

namespace verify {

// The rules of the program: its target's pointers are the runtime's
// words; each function's declared effects cover what its body may do; a
// memo sum is held only in a cell; past the higher stage containment in
// place is acyclic and no data type has a field of a closure or a
// suspension; and once the program is counted every idr.cell.recycle gives
// a cell of its token's layout. A lowered program is upstream's functions
// and globals, which hold no rule of ours.
mlir::LogicalResult program(ProgramOp program);

// No array can hold a reference to itself, by the cycles of `graph`, else
// the refusal `cycle`: the body of idr-knots, which runs once every closure
// is a constructor of a sum.
mlir::LogicalResult knots(ProgramOp program, const TypeGraph &graph);

// The rules of one function at its program's stage: what the stage lets its
// values hold; closures' flow while they exist; the one linearity rule; and
// the lifetimes' rules.
mlir::LogicalResult function(FuncOp fn);

// The one linearity rule of `fn`, after every pass. A value used once (by
// its type, or by its grade's uses) is used at most once on every path:
// the IR's linearity is affine, as Idris's quantity 1 lets a value go
// unused on a path that ends the run. Once its program is counted, a value
// that holds a reference of its own (counted), a cell, a reuse token and a
// package are given up exactly once on every path that goes on; a token is
// never used many times, and no dup or drop takes a value used once. Uses
// are counted on the worst path: the most over a match's alternatives, the
// sum over regions that run one after another, twice for a region that
// runs again; a path that ends the run gives nothing up.
mlir::LogicalResult linearity(FuncOp fn);

// The lifetimes' rules of `fn`, each local, none following a def-use
// chain: no lifetime is a terminator's operand or a result of an op that
// gives none; a value that flows from one lifetime into another lives in
// one that outlives it (by dominance: the open binders of one walk);
// inside a stack lifetime nothing is put into an older cursor; every slot
// lies in its lifetime's own run; and every lifetime carries its proof of
// the frame-limited rule, its cells bounded until its end or each
// reachable from what is still to be used.
mlir::LogicalResult lifetimes(FuncOp fn);

// Whether at most one region of `branch` runs: each returns straight to
// the op, as a match's or an scf.if's do, and none to another region.
bool alternatives(mlir::RegionBranchOpInterface branch);

} // namespace verify
} // namespace idr

#endif // IDR_IR_VERIFY_H
