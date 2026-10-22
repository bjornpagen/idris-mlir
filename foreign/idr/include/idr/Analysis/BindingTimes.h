// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What specialization decides by: the binding time of every parameter of a
// function, among the functions of its component of calls. A call
// specializes on a static argument only at a fixed parameter, where one
// specialization serves the whole recursion, whose calls then have its key.
// The answer is the optimizer's alone and dies with its run.
//
// The solve is sized by the program. Each member's body is read once into
// its edges: a call of a member passes, at each argument, one of the
// caller's parameters unchanged or anything. Then, per member taken as the
// root, one monovariant solve over (member, parameter) nodes with a flat
// lattice: nothing reached yet, the root's parameter k unchanged, or
// anything. A node rises at most twice, so a root costs O(members x
// parameters + edges), never a state per tuple of abstract arguments.
#ifndef IDR_ANALYSIS_BINDINGTIMES_H
#define IDR_ANALYSIS_BINDINGTIMES_H

#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"

#include <cstdint>
#include <utility>
#include <vector>

namespace idr {

// The binding time of one parameter, in the order of the join: fixed when
// every call of the function from its component passes the parameter on
// unchanged in its own position; varies otherwise. A function on no cycle
// meets no such call, so every parameter of it is fixed.
enum class BindingTime : std::uint8_t { Fixed, Varies };

// The name idr-binding-times reports a binding time by, indexed by it.
inline constexpr llvm::StringLiteral bindingTimeNames[] = {"fixed", "varies"};
inline llvm::StringRef nameOf(BindingTime time) {
  return bindingTimeNames[std::to_underlying(time)];
}

// The binding times of every member of `component`, in its order, one per
// parameter: each the join over the calls of the member that it reaches
// through the calls between the members. A value is a parameter passed on
// unchanged when idr::sourceOf finds it the same value as the parameter (an
// op that only changes a grade, a match's default region). Each body is
// read as it is now; nothing outside `component` is read.
template <solver::FunctionNames N>
std::vector<llvm::SmallVector<BindingTime>>
bindingTimesOf(const N &names, llvm::ArrayRef<solver::Member> component);

extern template std::vector<llvm::SmallVector<BindingTime>>
bindingTimesOf<solver::ProgramGraph>(const solver::ProgramGraph &,
                                     llvm::ArrayRef<solver::Member>);
extern template std::vector<llvm::SmallVector<BindingTime>>
bindingTimesOf<solver::Editor>(const solver::Editor &, llvm::ArrayRef<solver::Member>);

} // namespace idr

#endif // IDR_ANALYSIS_BINDINGTIMES_H
