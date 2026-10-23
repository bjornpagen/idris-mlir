// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Lending to upstream's ops. An op of upstream's takes only the bare
// carrier, and a pass may grade a tensor or a buffer such an op reads (a
// claim raised, a view made of a parameter), so every read of a holder by
// an op of upstream's is made a read of a loan (idr.carrier), which no one
// counts or grades: the holder keeps its grade, and the op its bare type.
// The lifetime pass lends every function before a reference is counted, so
// no pass after it meets a holder an op of upstream's takes; a pass that
// grades a holder before then lends it where it writes the grade.
#ifndef IDR_TRANSFORMS_LIFETIMES_LEND_H
#define IDR_TRANSFORMS_LIFETIMES_LEND_H

#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/IR/Func.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Value.h"
#include "llvm/ADT/ArrayRef.h"

#include <cstdint>

namespace idr::lifetimes {

// Whether `use` is a read by an op of upstream's, which takes only the bare
// carrier: an op of another dialect that neither forwards its operands into
// a region nor out of one, since what a region branch forwards is a
// position, which takes any type.
bool readByUpstream(mlir::OpOperand &use);

// What a lending changed: the lifetimes it opened and the reads it gave a
// loan or a share.
struct Lending {
  unsigned opened = 0;
  unsigned rewritten = 0;

  // Two lendings' changes, one after the other: what a pass that lends
  // many functions, or one holder by parts, reports.
  Lending &operator+=(const Lending &more) {
    opened += more.opened;
    rewritten += more.rewritten;
    return *this;
  }
};

// Each of `holders`, values of `fn` (function `self` of `graph`) that ops
// of upstream's read, given to those ops by who frees it, by a carrier
// under a lifetime's view (the lifetime itself, or its view where it is of
// another kind), and no loan changes a count. A scoped holder is projected
// under its own lifetime and a static one under this activation's (static
// data outlives every lifetime), a carrier at each read. A scoped holder's
// carrier stands on its read's stretch, the read and every use of its
// aliases, none going out of it and no call in it that runs on a frame, so
// no alias of it leaves its lifetime or is held by a frame. A counted one
// is lent under view lifetimes opened on the stretch of its reads, the
// innermost block's ops from the first use of the loan to the last, cut at
// each op no loan's region may hold (one holding a call that runs on a
// frame, a call in tail position, a jump out): the reads on each side of
// the cuts are one loan, a view made on one side and read on another made
// again on that side of its own loan, and the reads inside a cut are lent
// again inside it. A read one of whose aliases goes out of the loan (out of
// the function, into memory, into an op of ours, or on through a region
// branch) is no loan: the alias takes a reference of its own, so the holder
// is shared into that read, as it would be with no lifetime, a share's
// result being a value no flow explains, which no pass grades. A loan read
// by a cut itself, or with an alias read across a cut that no op can make
// again, is an internal error naming the op. A tensor an op of upstream's
// writes is taken over by that op, its result the tensor's next version,
// so a holder at a grade past its bare one is shared into it.
Lending lend(FuncOp fn, solver::FunctionId self, const solver::ProgramGraph &graph,
             llvm::ArrayRef<mlir::Value> holders);

// Which holders a lending takes: those at a grade past their bare one,
// which a pass that writes a grade before counting lends where it writes
// it; or every one, which the lifetime pass lends, so that no pass after it
// meets a holder an op of upstream's takes.
enum class Holders : std::uint8_t { Graded, Every };

// Every value of `fn` an op of upstream's reads that `which` takes, and is
// no loan already, lent (lend).
Lending lendReads(FuncOp fn, solver::FunctionId self, const solver::ProgramGraph &graph,
                  Holders which);

// `loan` projected under `lifetime`, its holder's own once a pass has made
// the holder scoped, so a scoped holder's loan has one form; the view
// lifetime it was lent under, once nothing uses it, dissolved: its ops
// stand where it stood and its results are what its region yields.
void reproject(CarrierOp loan, mlir::Value lifetime);

} // namespace idr::lifetimes

#endif // IDR_TRANSFORMS_LIFETIMES_LEND_H
