-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Libraries.Text.Bounded

%default total


public export
record Bounds where
  constructor MkBounds
  ||| 0-based first line
  startLine : Int
  ||| 0-based first col
  startCol : Int
  ||| 0-based last line of bound
  endLine : Int
  ||| 0-based first column after bound
  endCol : Int

export
Show Bounds where
  showPrec d (MkBounds sl sc el ec) =
    showCon d "MkBounds" (concat [showArg sl, showArg sc, showArg el, showArg ec])

export
startBounds : Bounds -> (Int, Int)
startBounds b = (b.startLine, b.startCol)

export
endBounds : Bounds -> (Int, Int)
endBounds b = (b.endLine, b.endCol)

export
union : Bounds -> Bounds -> Bounds
union b1 b2 =
  let (ur, uc) = min (startBounds b1) (startBounds b2)
      (lr, lc) = max (endBounds b1) (endBounds b2)
   in MkBounds ur uc lr lc

export
Eq Bounds where
  (MkBounds sl sc el ec) == (MkBounds sl' sc' el' ec') =
      sl == sl'
   && sc == sc'
   && el == el'
   && ec == ec'

-- A token's and a parsed value's `val` and `bounds` are kept apart by
-- namespace, and found by type.
namespace Located
  ||| A token as a lexer gives it: always where it was read.
  public export
  record Located ty where
    constructor MkLocated
    val : ty
    bounds : Bounds

export
Eq ty => Eq (Located ty) where
  (MkLocated val bd) == (MkLocated val' bd') = val == val' && bd == bd'

export
Show ty => Show (Located ty) where
  showPrec d (MkLocated val bd) = showCon d "MkLocated" (concat [showArg val, showArg bd])

export
Functor Located where
  map f (MkLocated val bd) = MkLocated (f val) bd

||| A value a parser gives, with the bounds of the input it was parsed from.
||| A value parsed from no input (`pure`, a token only looked at) has none:
||| upstream kept a flag beside bounds that were junk when it was set, and
||| mapping a value, or sequencing it after `pure`, then changed its bounds,
||| so the functor and monad identities failed.
public export
data WithBounds : Type -> Type where
  Irrelevant : ty -> WithBounds ty
  Relevant : ty -> Bounds -> WithBounds ty

namespace WithBounds
  export
  val : WithBounds ty -> ty
  val (Irrelevant v) = v
  val (Relevant v _) = v

  export
  (.val) : WithBounds ty -> ty
  (.val) = val

  ||| Where the value was parsed from, unless it was parsed from no input.
  export
  (.bounds) : WithBounds ty -> Maybe Bounds
  (.bounds) (Irrelevant _) = Nothing
  (.bounds) (Relevant _ bd) = Just bd

||| A token as a value parsed from it.
export
fromLocated : Located ty -> WithBounds ty
fromLocated (MkLocated v bd) = Relevant v bd

export
Eq ty => Eq (WithBounds ty) where
  (Irrelevant v) == (Irrelevant v') = v == v'
  (Relevant v bd) == (Relevant v' bd') = v == v' && bd == bd'
  _ == _ = False

export
Show ty => Show (WithBounds ty) where
  showPrec d (Irrelevant v) = showCon d "Irrelevant" (showArg v)
  showPrec d (Relevant v bd) = showCon d "Relevant" (concat [showArg v, showArg bd])

export
Functor WithBounds where
  map f (Irrelevant v) = Irrelevant (f v)
  map f (Relevant v bd) = Relevant (f v) bd

export
Foldable WithBounds where
  foldr c n b = c (val b) n

export
Traversable WithBounds where
  traverse f (Irrelevant v) = Irrelevant <$> f v
  traverse f (Relevant v bd) = (\ v => Relevant v bd) <$> f v

||| The value of the second, at the bounds both together cover.
export
mergeBounds : WithBounds ty -> WithBounds ty' -> WithBounds ty'
mergeBounds (Irrelevant _) b2 = b2
mergeBounds (Relevant _ bd) (Irrelevant v) = Relevant v bd
mergeBounds (Relevant _ bd1) (Relevant v bd2) = Relevant v (union bd1 bd2)

export
joinBounds : WithBounds (WithBounds ty) -> WithBounds ty
joinBounds b = mergeBounds b (val b)
