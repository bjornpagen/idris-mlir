-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
module Smaller

%default total

halve : Nat -> Nat
halve (S (S n)) = S (halve (assert_smaller (S (S n)) n))
halve _ = Z
