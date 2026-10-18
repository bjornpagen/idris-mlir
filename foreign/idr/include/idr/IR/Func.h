// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What the dialect registers for idr.func, idr.call and idr.return beyond
// their ops, the inliner's rules, which mirror func's for its own; what a
// function's body does, of itself and with its calls, and the one writer of
// a function's effects and its calls'; how the dialect's effect bits are
// MLIR's resource effects; what a program's stage implies; and what a
// program's root is.
#ifndef IDR_IR_FUNC_H
#define IDR_IR_FUNC_H

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/Support/ErrorHandling.h"

#include <optional>

namespace idr {

// Every call, op and region of the dialect may be inlined; a return becomes
// the values it gives back.
void addInlinerInterface(IdrDialect &dialect);

// What `fn`'s body does of itself, its calls aside: not return unless Idris
// proved it total; perform IO where a parameter may hold a world or the
// body forges one; crash where an op may crash; and anything where an op
// runs a label (an apply, a force), whose function no symbol names. The one
// rule: componentEffects and the program's verifier both read it. The ops'
// memory effects are not it: a possible crash also writes the IO resource,
// and an op may read that resource with no world.
Effect bodyEffect(FuncOp fn);

// What every member of `component`, a component of the call graph, may do:
// each member's own part (bodyEffect), and the effects of each call in a
// member's body of a function outside the component, which `symbols`, the
// program's table, resolves. Every such callee is final when this is asked,
// and its calls hold its effects (writeEffects); a call of a member adds
// nothing, its body being in the sum. It reads the members' bodies alone, so
// disjoint components may be asked from different workers.
Effect componentEffects(llvm::ArrayRef<FuncOp> component, const mlir::SymbolTable &symbols);

// Gives `fn` the effects `effects`, and every idr.call of it among `users`
// (the symbol's users, upstream's map, built where no worker holds a caller)
// the same: the one writer of a function's effects, so a call never holds
// less than its callee, which its verifier refuses.
void writeEffects(FuncOp fn, Effect effects, const mlir::SymbolUserMap &users);

// The resource effects that the dialect's bits stand for, one table, each
// row once per bit `effects` holds: io reads and writes the IO resource; a
// crash writes the crash resource and the IO resource, as the end of the
// program's output, so nothing is moved across output past a crash; not
// returning writes the divergence resource. What a call declares to MLIR.
void effectInstances(Effect effects,
                     llvm::SmallVectorImpl<mlir::MemoryEffects::EffectInstance> &instances);

// What a program's stage implies of its functions and data types, written
// in stageFacts alone, whose switch has no default, so that a new stage
// decides every fact in one place and no reader holds a stage boolean of
// its own. No other code makes one.
class StageFacts {
public:
  // Closures and suspensions remain, which idr-defunctionalize makes sums,
  // and with them the types that contain themselves in place, which it
  // boxes (layout::fit).
  constexpr bool closures() const { return withClosures; }
  // Every value of ours that holds a reference is graded own, excl or
  // borrow, which idr-rc's grades step does: no plain one is left, and an
  // own or excl grade and an adopted buffer are admitted.
  constexpr bool grades() const { return withGrades; }
  // References are counted exactly, which idr-rc's placement makes, building
  // the program's cells: the count walk holds every function to it.
  constexpr bool counted() const { return withCounts; }
  // The program's functions are idr.func; a lowered program holds
  // upstream's functions and globals in their place.
  constexpr bool idrFunctions() const { return withIdrFunctions; }

private:
  constexpr StageFacts(bool closures, bool grades, bool counts, bool idrFunctions)
      : withClosures(closures), withGrades(grades), withCounts(counts),
        withIdrFunctions(idrFunctions) {}
  friend constexpr StageFacts stageFacts(Stage stage);

  bool withClosures;
  bool withGrades;
  bool withCounts;
  bool withIdrFunctions;
};

constexpr StageFacts stageFacts(Stage stage) {
  switch (stage) {
  case Stage::Higher:
    return StageFacts(/*closures=*/true, /*grades=*/false, /*counts=*/false,
                      /*idrFunctions=*/true);
  case Stage::First:
    return StageFacts(/*closures=*/false, /*grades=*/false, /*counts=*/false,
                      /*idrFunctions=*/true);
  case Stage::Graded:
    return StageFacts(/*closures=*/false, /*grades=*/true, /*counts=*/false,
                      /*idrFunctions=*/true);
  case Stage::Owned:
    return StageFacts(/*closures=*/false, /*grades=*/true, /*counts=*/true,
                      /*idrFunctions=*/true);
  case Stage::Lowered:
    return StageFacts(/*closures=*/false, /*grades=*/true, /*counts=*/true,
                      /*idrFunctions=*/false);
  }
  llvm_unreachable("a stage of the program");
}

// What a program's root is: Status, whose result is the program's exit
// status; IO, whose run is the program and whose results hold nothing the
// program reports.
enum class RootKind { Status, IO };

// The kind of root a function of `type` is in a program at `stage`, the one
// rule of the root, which the program's verifier holds and idr-entry trusts:
// `() -> i64` is Status at every stage; before lowering (higher, first,
// graded, owned: the stages of idr.func), a function of the world alone
// whose every result holds no runtime component
// (layout::holdsNoComponent: the world, a unit, the frontend's IO result of
// a unit) is IO; lowered, `() -> ()` is IO. Any other type is no root.
std::optional<RootKind> rootKind(mlir::FunctionType type, Stage stage);

} // namespace idr

#endif // IDR_IR_FUNC_H
