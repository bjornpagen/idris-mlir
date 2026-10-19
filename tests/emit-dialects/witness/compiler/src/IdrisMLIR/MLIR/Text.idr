-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
module IdrisMLIR.MLIR.Text

export
opName : String -> String
opName name = "memref." ++ name
