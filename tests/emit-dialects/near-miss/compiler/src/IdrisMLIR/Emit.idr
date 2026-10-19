-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
module IdrisMLIR.Emit

-- "arith.addi" is written by IdrisMLIR.Dialect.Arith, not here
export
names : List String
names = ["arith", "llvm.func", "func.call", "arithmetic.addi", "scf.for", "idr"]

note : String
note = "x != y, #1 and a.b are no names"
