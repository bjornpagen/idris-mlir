-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
module IdrisMLIR.Fold

fold : Int -> Int -> Int
fold a b = prim__add_Int a b
