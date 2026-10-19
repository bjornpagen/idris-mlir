-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
module Partial

%default total

export
partial
loop : Nat -> Nat
loop n = loop (S n)
