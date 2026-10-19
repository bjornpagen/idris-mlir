-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
module Trusted

%default total

export
covering
host : Nat -> Nat
host n = n

whole : Nat -> Nat
whole n = assert_total (host n)
