-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
module IdrisMLIR.Frontend.Tree

tree : GlobalDef -> CaseTree vars
tree def = def.treeRT
