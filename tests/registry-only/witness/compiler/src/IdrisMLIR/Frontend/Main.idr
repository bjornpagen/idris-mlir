-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
module IdrisMLIR.Frontend.Main

mainName : Name
mainName = NS (mkNamespace "Main") (UN (Basic "main"))
