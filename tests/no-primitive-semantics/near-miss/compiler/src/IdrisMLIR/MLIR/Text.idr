-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
module IdrisMLIR.MLIR.Text

-- prim__add_Int in a comment computes nothing
||| nor prim__mul_Int in documentation
name : String
name = "prim__add_Int"

myprim__count : Nat
myprim__count = 0

double : Double -> String
double d = decimal (prim__cast_DoubleString d)
