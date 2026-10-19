-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
module IdrisMLIR.Shift

shift : Int -> Int -> Int
shift a b = Prelude.prim__shl_Int a b
