// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What specialization decides by: the binding time of every parameter of a
// function, among the functions of its cycle of calls. A call specializes
// on a static argument only at a fixed parameter, where one specialization
// serves the whole recursion, whose calls then have its key.
#ifndef IDR_ANALYSIS_BINDINGTIMES_H
#define IDR_ANALYSIS_BINDINGTIMES_H

#include "idr/IR/IdrDialect.h"

#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"

#include <cstdint>

namespace idr {

// The binding time of one parameter, in the order of the join, which is
// the larger of two: fixed when every call of the function from its
// component passes the parameter on unchanged in its own position; varies
// otherwise. A function on no cycle meets no such call, so every parameter
// of it is fixed.
enum class BindingTime : uint8_t { Fixed, Varies };

// The name idr-binding-times reports a binding time by.
llvm::StringRef nameOf(BindingTime time);

// One binding time per parameter of `fn`, a member of `component`: the
// join over the calls of `fn` that `fn` reaches through the calls between
// the members. A value is a parameter passed on unchanged when idr::sourceOf
// finds it the same value as the parameter (an op that only changes a
// grade, a match's default region). Each body is read as it is now;
// nothing outside `component` is read.
llvm::SmallVector<BindingTime> bindingTimesOf(idr::FuncOp fn,
                                              llvm::ArrayRef<idr::FuncOp> component);

} // namespace idr

#endif // IDR_ANALYSIS_BINDINGTIMES_H
