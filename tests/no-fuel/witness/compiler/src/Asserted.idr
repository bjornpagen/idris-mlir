-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
module Asserted

%default total

loop : Nat -> Nat
loop n = assert_total (loop n)
