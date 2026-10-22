-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Libraries.Data.StringTrie

import Data.These
import Libraries.Data.StringMap

%default total

-- prefix tree specialised to use `String`s as keys

public export
record StringTrie a where
  constructor MkStringTrie
  node : These a (StringMap (StringTrie a))

public export
empty : StringTrie a
empty = MkStringTrie $ That empty

public export
singleton : List String -> a -> StringTrie a
singleton []      v = MkStringTrie $ This v
singleton (k::ks) v = MkStringTrie $ That $ singleton k (singleton ks v)

-- insert using supplied function to resolve clashes
public export
insertWith : List String -> (Maybe a -> a) -> StringTrie a -> StringTrie a
insertWith []      f (MkStringTrie nd) =
  MkStringTrie $ these (This . f . Just) (Both (f Nothing)) (Both . f . Just) nd
insertWith (k::ks) f (MkStringTrie nd) =
  MkStringTrie $ these (\x => Both x (singleton k end)) (That . rec) (\x => Both x . rec) nd
  where
  end : StringTrie a
  end = singleton ks (f Nothing)
  rec : StringMap (StringTrie a) -> StringMap (StringTrie a)
  rec sm = maybe (insert k end sm) (\tm => insert k (insertWith ks f tm) sm) (lookup k sm)

public export
insert : List String -> a -> StringTrie a -> StringTrie a
insert ks v = insertWith ks (const v)

-- Each walker takes apart the part it is given, a node's map, the map's
-- tree or a leaf's trie, so every call is on a part of the one before it.
mutual
  -- A node's value first, then its children.
  foldNode : (Monad m, Monoid b) =>
             (List String -> m b) -> (List String -> a -> m b) ->
             List String -> These a (StringMap (StringTrie a)) -> m b
  foldNode fk fv ks (This x) = fv ks x
  foldNode fk fv ks (That sm) = foldChildren fk fv ks neutral sm
  foldNode fk fv ks (Both x sm)
      = do y <- fv ks x
           z <- foldChildren fk fv ks neutral sm
           pure (y <+> z)

  -- The children in their keys' order, each followed by its own path's
  -- action, accumulated from the left.
  foldChildren : (Monad m, Monoid b) =>
                 (List String -> m b) -> (List String -> a -> m b) ->
                 List String -> b -> StringMap (StringTrie a) -> m b
  foldChildren fk fv ks acc Empty = pure acc
  foldChildren fk fv ks acc (M _ t) = foldTree fk fv ks acc t

  foldTree : (Monad m, Monoid b) =>
             (List String -> m b) -> (List String -> a -> m b) ->
             List String -> b -> Tree n (StringTrie a) -> m b
  foldTree fk fv ks acc (Leaf k (MkStringTrie nd))
      = do let ks' = ks ++ [k]
           y <- foldNode fk fv ks' nd
           z <- fk ks'
           pure (acc <+> y <+> z)
  foldTree fk fv ks acc (Branch2 t1 _ t2)
      = do acc1 <- foldTree fk fv ks acc t1
           foldTree fk fv ks acc1 t2
  foldTree fk fv ks acc (Branch3 t1 _ t2 _ t3)
      = do acc1 <- foldTree fk fv ks acc t1
           acc2 <- foldTree fk fv ks acc1 t2
           foldTree fk fv ks acc2 t3

||| Folds a trie's paths: at each node its value's action on the node's path,
||| then each child in its key's order, the child's own nodes first and then
||| `fk` on the child's path.
export
foldWithKeysM : (Monad m, Monoid b) =>
                (List String -> m b) -> (List String -> a -> m b) ->
                StringTrie a -> m b
foldWithKeysM fk fv (MkStringTrie nd) = foldNode fk fv [] nd
