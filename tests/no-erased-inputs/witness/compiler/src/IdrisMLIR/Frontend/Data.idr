-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
module IdrisMLIR.Frontend.Data

export
read : Ref Ctxt Defs -> Core (CompileData)
read c = getCompileData False Cases
