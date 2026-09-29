// What code may do besides computing its results, for the passes that drop,
// move or run it at compile time. Every function carries what idr-effects
// finds, `idr.effects`, and what Idris proves, `idr.total`; the questions
// below read those and the ops themselves, nothing else.
#pragma once

#include "idr/Idr.h"

#include <optional>

namespace idr::facts {

// What running some code may do besides computing its results and
// allocating them: perform IO (or anything at all), crash, or fail to
// return.
struct Effects {
  bool io = false;
  bool crash = false;
  bool partial = false;

  static Effects all() { return {true, true, true}; }
  bool none() const { return !io && !crash && !partial; }
  Effects &operator|=(const Effects &other) {
    io |= other.io;
    crash |= other.crash;
    partial |= other.partial;
    return *this;
  }
};

// What a call of `fn` may do. A null function (one the module lacks), a
// function without a body, or one without `idr.effects` may do anything;
// one without `idr.total` may not return.
Effects of(mlir::func::FuncOp fn);

// Writes what idr-effects found, `io` and `crash`, as `idr.effects`; whether
// `fn` returns is Idris's fact, `idr.total`.
void record(mlir::func::FuncOp fn, Effects effects);

// Whether a value of `type` may hold a world: a world, or data with a field
// that may. A closure never captures one, so a world reaches a function
// only through its parameters.
bool mayHoldWorld(mlir::Operation *from, mlir::Type type);

// Whether `fn` takes a world, in a parameter or in data one holds.
bool takesWorld(mlir::func::FuncOp fn);

// The label that `ctor` names when it builds a closure: the sums of
// closures that idr-defunctionalize makes (`@fn$<n>`) have one constructor
// per label, named after its function. Null for any other constructor.
mlir::StringAttr closureLabel(mlir::SymbolRefAttr ctor);

// Whether a value of `type` may hold a closure: a closure, a sum of
// closures that idr-defunctionalize made, or data with a field that may.
bool mayHoldClosure(mlir::Operation *from, mlir::Type type);

// What code given `value` may do by applying the closures it holds: what
// their labels do, through captures and fields. A closure whose label is
// not known where `value` is made may do anything.
Effects passed(mlir::Operation *from, mlir::Value value);

// Whether `op` only computes: nothing in it performs IO, crashes or may
// not return, and every call in it is of a function that does none of
// these, given closures that do none of these. It may then move across any
// op, and any op across it, run on fewer paths, or not at all.
bool canMoveAcross(mlir::Operation *op);

// Whether `op` may run later, past ops that only compute, as long as it
// still runs on every path it runs on now: nothing in it performs IO, but
// it may crash or not return, since nothing that could observe the
// difference comes between.
bool canDelay(mlir::Operation *op);

// Whether `call`, whose results are unused, may go: it only computes.
bool canDrop(mlir::func::CallOp call);

// A call idr-eval may run at compile time: a func.call, or an idr.apply of
// a constant closure, whose operands are all constants. `args` are the
// captures of the closure, then the operands. The callee and every
// function the constants name as closures have bodies and perform no IO; a
// crash or a call that does not finish stays for runtime. `total`: all of
// them are total, so the call runs with the larger budget.
struct Evaluation {
  mlir::func::FuncOp callee;
  llvm::SmallVector<mlir::Attribute> args;
  bool total;
};
std::optional<Evaluation> canEvaluate(mlir::Operation *call, mlir::SymbolTable &symbols);

// Gives `made`, a new function that runs the body of `origin` with closures
// of `labels` in it (a clone), the facts idr-effects would find: those of
// `origin` and of `labels` together (a null label, one not known, may do
// anything), and IO if it takes a world.
void inherit(mlir::func::FuncOp made, mlir::func::FuncOp origin,
             llvm::ArrayRef<mlir::func::FuncOp> labels);

// Whether `fn` was written in a library module.
bool isLibrary(mlir::func::FuncOp fn);

} // namespace idr::facts
