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
