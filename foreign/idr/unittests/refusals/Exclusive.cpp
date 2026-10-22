// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A value that owns its whole cell graph alone has one owner: its handle
// moves and never copies, and only the parse of its type makes one.

#include "idr/IR/Quantities.h"

#include "mlir/IR/Value.h"

#include <optional>
#include <utility>

std::optional<idr::Exclusive> parsed(mlir::Value value) { return idr::asExclusive(value); }

idr::Exclusive handedOn(idr::Exclusive owner) { return idr::Exclusive(std::move(owner)); }

void duplicated(const idr::Exclusive &owner) {
  idr::Exclusive second(owner); // expected-error {{an exclusive value has one owner}}
}

void forged(mlir::Value value) {
  idr::Exclusive claimed(value); // expected-error {{calling a private constructor of class 'idr::Exclusive'}}
}
