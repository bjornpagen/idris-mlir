-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
module IdrisMLIR.Types

isPrelude : String -> Bool
isPrelude ns = ns == "Prelude"
