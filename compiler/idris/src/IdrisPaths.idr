module IdrisPaths

-- Upstream's build generates this module with the version and the install
-- prefix. The fork has no install of its own to point at: whoever drives
-- it passes the prefix explicitly. What remains is the version: upstream's
-- release, tagged with the commit the fork tracks (the gitlink of
-- third_party/Idris2), which a re-sync moves with it.
export
idrisVersion : ((Nat,Nat,Nat), String)
idrisVersion = ((0,8,0), "1c630e67c")
