-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2026 Bjorn Pagen
module IdrisPaths

-- Upstream's build generates this module with the version and the install
-- prefix. The checker has no install of its own to point at: whoever
-- drives it passes the prefix explicitly. What remains is the version: the
-- release of Idris the checker was copied from, tagged with the commit it
-- was copied at.
export
idrisVersion : ((Nat,Nat,Nat), String)
idrisVersion = ((0,8,0), "1c630e67c")
