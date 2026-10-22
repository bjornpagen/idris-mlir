-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2026 Bjorn Pagen
||| Classes of keys made one by merging, each with a payload its members
||| share. It merges and finds; it never searches.
|||
||| Every member names its class's root directly, so finding a class is one
||| lookup and needs no recursion; a merge renames the members of the
||| smaller class, so a key is renamed at most logarithmically often in the
||| number of keys. It is persistent: an elaborator that tries a branch and
||| backtracks keeps the classes it had, with the rest of its state.
|||
||| The keys are open: elaboration makes new ones as it goes. A key no merge
||| has reached is a class of its own, with the neutral payload, and the
||| structure holds nothing for it, as a sparse matrix holds nothing for a
||| zero.
module Libraries.Data.UnionFind

import Libraries.Data.IntMap

%default total

||| A class with more than its root, or a payload: its other members and how
||| many keys it holds.
record Class p where
  constructor MkClass
  others : List Int
  size : Nat
  payload : p

export
record UnionFind p where
  constructor MkUnionFind
  -- each merged key that is not its class's root, to that root
  rootOf : IntMap Int
  -- each root with other members or a payload, to its class
  classes : IntMap (Class p)

export
empty : UnionFind p
empty = MkUnionFind IntMap.empty IntMap.empty

||| The root of a key's class: itself when no merge has reached it.
export
root : Int -> UnionFind p -> Int
root k uf = case lookup k uf.rootOf of
                 Just r => r
                 Nothing => k

classAt : Monoid p => Int -> UnionFind p -> Class p
classAt r uf = case lookup r uf.classes of
                    Just c => c
                    Nothing => MkClass [] 1 neutral

||| Adds to the payload of a key's class.
export
addTo : Monoid p => Int -> p -> UnionFind p -> UnionFind p
addTo k x uf
    = let r = root k uf
          c = classAt r uf in
          { classes $= insert r ({ payload := c.payload <+> x } c) } uf

||| Takes the payload of a key's class out of it, leaving the neutral one.
export
takeFrom : Monoid p => Int -> UnionFind p -> (p, UnionFind p)
takeFrom k uf
    = let r = root k uf
          c = classAt r uf in
          (c.payload, { classes $= insert r ({ payload := neutral } c) } uf)

||| Makes the classes of two keys one, their payloads joined. The smaller
||| class's members are renamed to the larger's root.
export
merge : Monoid p => Int -> Int -> UnionFind p -> UnionFind p
merge a b uf
    = let ra = root a uf
          rb = root b uf in
          if ra == rb
             then uf
             else let ca = classAt ra uf
                      cb = classAt rb uf in
                      if ca.size <= cb.size
                         then into ra ca rb cb
                         else into rb cb ra ca
  where
    -- The class at the root `src` joins the class at the root `dst`.
    into : Int -> Class p -> Int -> Class p -> UnionFind p
    into src csrc dst cdst
        = let moved = src :: csrc.others in
              MkUnionFind
                (foldl (\m, k => insert k dst m) uf.rootOf moved)
                (insert dst (MkClass (moved ++ cdst.others)
                                     (csrc.size + cdst.size)
                                     (cdst.payload <+> csrc.payload))
                        (delete src uf.classes))
