-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Core.Hash

import Core.Case.CaseTree
import Core.Core
import Core.TT

import Data.List1
import Data.Vect

import Libraries.Data.List.SizeOf

%default covering

-- This is so that we can store a hash of the interface in ttc files, to avoid
-- the need for reloading modules when no interfaces have changed in imports.
-- As you can probably tell, I know almost nothing about writing good hash
-- functions, so better implementations will be very welcome...

public export
interface Hashable a where
  hash : a -> Int
  hashWithSalt : Int -> a -> Int

  hash = hashWithSalt 5381
  hashWithSalt h i = h * 33 + hash i

export infixl 5 `hashWithSalt`

export
Hashable Int where
  hash = id

export
Hashable Int8 where
  hash = cast

export
Hashable Int16 where
  hash = cast

export
Hashable Int32 where
  hash = cast

export
Hashable Int64 where
  hash = cast

export
Hashable Bits8 where
  hash = cast

export
Hashable Bits16 where
  hash = cast

export
Hashable Bits32 where
  hash = cast

export
Hashable Bits64 where
  hash = cast

export
Hashable Integer where
  hash = fromInteger

export
Hashable Nat where
  hash = cast

export
Hashable Char where
  hash = cast

export
Hashable a => Hashable (Vect n a) where
  hashWithSalt h [] = abs h
  hashWithSalt h (x :: xs) = hashWithSalt (h * 33 + hash x) xs

export
Hashable a => Hashable (List a) where
  hashWithSalt h [] = abs h
  hashWithSalt h (x :: xs) = hashWithSalt (h * 33 + hash x) xs

export
Hashable a => Hashable (SnocList a) where
  hashWithSalt h [<] = abs h
  hashWithSalt h (xs :< x) = hashWithSalt (h * 33 + hash x) xs

export
Hashable a => Hashable (List1 a) where
  hashWithSalt h xxs = hashWithSalt (h * 33 + hash (head xxs)) (tail xxs)

export
Hashable a => Hashable (Maybe a) where
  hashWithSalt h Nothing = abs h
  hashWithSalt h (Just x) = hashWithSalt h x

export
Hashable a => Hashable b => Hashable (a, b) where
  hashWithSalt h (x, y) = h `hashWithSalt` x `hashWithSalt` y

export
Hashable String where
  -- each character in order, as the salt of the next (not `List Char`'s
  -- hash, which also takes the absolute value at the end)
  hashWithSalt h str = foldl hashWithSalt h (unpack str)

export
Hashable Double where
  hash = hash . show

-- An identifier hashes as its text: a hash written to a TTC is of
-- content, the same in every session, never of the ids a session gave.
export
Hashable Ident where
  hashWithSalt h i = hashWithSalt h i.text

export
Hashable Namespace where
  hashWithSalt h ns = hashWithSalt h (unsafeUnfoldNamespace ns)

export
Hashable Name where
  hashWithSalt h (MN s _) = hashWithSalt h s
  hashWithSalt h (DN _ n) = hashWithSalt h n
  hashWithSalt h (NS ns n) = hashWithSalt (hashWithSalt h ns) n
  hashWithSalt h (Resolved i) = hashWithSalt h i
  hashWithSalt h n = hashWithSalt h (show n)

export
Hashable RigCount where
  hashWithSalt h = elimSemi
                     (hashWithSalt h 0)
                     (hashWithSalt h 1)
                     (const $ hashWithSalt h 2)

export
Hashable t => Hashable (PiInfo t) where
  hashWithSalt h Implicit = hashWithSalt h 0
  hashWithSalt h Explicit = hashWithSalt h 1
  hashWithSalt h AutoImplicit = hashWithSalt h 2
  hashWithSalt h (DefImplicit t) = h `hashWithSalt` 3 `hashWithSalt` t

export
Hashable ty => Hashable (Binder ty) where
  hashWithSalt h (Lam _ c p ty)
      = h `hashWithSalt` 0 `hashWithSalt` c `hashWithSalt` p `hashWithSalt` ty
  hashWithSalt h (Let _ c val ty)
      = h `hashWithSalt` 1 `hashWithSalt` c `hashWithSalt` val `hashWithSalt` ty
  hashWithSalt h (Pi _ c p ty)
      = h `hashWithSalt` 2 `hashWithSalt` c `hashWithSalt` p `hashWithSalt` ty
  hashWithSalt h (PVar _ c p ty)
      = h `hashWithSalt` 3 `hashWithSalt` c `hashWithSalt` p `hashWithSalt` ty
  hashWithSalt h (PLet _ c val ty)
      = h `hashWithSalt` 4 `hashWithSalt` c `hashWithSalt` val `hashWithSalt` ty
  hashWithSalt h (PVTy _ c ty)
      = h `hashWithSalt` 5 `hashWithSalt` c `hashWithSalt` ty

Hashable (Var vars) where
  hashWithSalt h (MkVar {varIdx = i} _) = hashWithSalt h i

export
Hashable LazyReason where
  hashWithSalt h = \case
    LInf => h `hashWithSalt` 0
    LLazy => h `hashWithSalt` 1
    LUnknown => h `hashWithSalt` 2

export
Hashable DelayOrigin where
  hashWithSalt h = \case
    InSource => h `hashWithSalt` 0
    ByElaborator => h `hashWithSalt` 1

-- Both: an interface's hash changes when what a reader of its terms sees
-- does, and where a delay came from is read.
export
Hashable Delaying where
  hashWithSalt h d = h `hashWithSalt` d.reason `hashWithSalt` d.origin

-- A term's hash is the one its nodes' instances would give, each kind of
-- node that holds terms hashed by a function of its own, so that every
-- recursive call is on a part of its argument.
mutual
  hashPi : Int -> PiInfo (Term vars) -> Int
  hashPi h Implicit = hashWithSalt h 0
  hashPi h Explicit = hashWithSalt h 1
  hashPi h AutoImplicit = hashWithSalt h 2
  hashPi h (DefImplicit t) = hashTerm (h `hashWithSalt` 3) t

  hashBinder : Int -> Binder (Term vars) -> Int
  hashBinder h (Lam _ c p ty)
      = hashTerm (hashPi (h `hashWithSalt` 0 `hashWithSalt` c) p) ty
  hashBinder h (Let _ c val ty)
      = hashTerm (hashTerm (h `hashWithSalt` 1 `hashWithSalt` c) val) ty
  hashBinder h (Pi _ c p ty)
      = hashTerm (hashPi (h `hashWithSalt` 2 `hashWithSalt` c) p) ty
  hashBinder h (PVar _ c p ty)
      = hashTerm (hashPi (h `hashWithSalt` 3 `hashWithSalt` c) p) ty
  hashBinder h (PLet _ c val ty)
      = hashTerm (hashTerm (h `hashWithSalt` 4 `hashWithSalt` c) val) ty
  hashBinder h (PVTy _ c ty)
      = hashTerm (h `hashWithSalt` 5 `hashWithSalt` c) ty

  -- As a list hashes: each element's own hash in turn.
  hashTerms : Int -> List (Term vars) -> Int
  hashTerms h [] = abs h
  hashTerms h (t :: ts) = hashTerms (h * 33 + hashTerm 5381 t) ts

  total
  hashTerm : Int -> Term vars -> Int
  hashTerm h (Local fc x idx y)
      = h `hashWithSalt` 0 `hashWithSalt` idx
  hashTerm h (Ref fc x name)
      = h `hashWithSalt` 1 `hashWithSalt` name
  hashTerm h (Meta fc x y xs)
      = hashTerms (h `hashWithSalt` 2 `hashWithSalt` y) xs
  hashTerm h (Bind fc x b scope)
      = hashTerm (hashBinder (h `hashWithSalt` 3) b) scope
  hashTerm h (App fc fn arg)
      = hashTerm (hashTerm (h `hashWithSalt` 4) fn) arg
  hashTerm h (As fc _ nm pat)
      = hashTerm (hashTerm (h `hashWithSalt` 5) nm) pat
  hashTerm h (TDelayed fc x y)
      = hashTerm (h `hashWithSalt` 6) y
  hashTerm h (TDelay fc d t y)
      = hashTerm (hashTerm (h `hashWithSalt` 7 `hashWithSalt` d) t) y
  hashTerm h (TForce fc r x)
      = hashTerm (h `hashWithSalt` 8) x
  hashTerm h (PrimVal fc c)
      = h `hashWithSalt` 9 `hashWithSalt` (show c)
  hashTerm h (Erased fc _)
      = hashWithSalt h 10
  hashTerm h (TType fc u)
      = hashWithSalt h 11 `hashWithSalt` u

export
Hashable (Term vars) where
  hashWithSalt = hashTerm

mutual
  export
  Hashable Pat where
    hashWithSalt h (PAs fc nm pat)
        = h `hashWithSalt` 0 `hashWithSalt` nm `hashWithSalt` pat
    hashWithSalt h (PCon fc x tag arity xs)
        = h `hashWithSalt` 1 `hashWithSalt` x `hashWithSalt` xs
    hashWithSalt h (PTyCon fc x arity xs)
        = h `hashWithSalt` 2 `hashWithSalt` x `hashWithSalt` xs
    hashWithSalt h (PConst fc c)
        = h `hashWithSalt` 3 `hashWithSalt` (show c)
    hashWithSalt h (PArrow fc x s t)
        = h `hashWithSalt` 4 `hashWithSalt` s `hashWithSalt` t
    hashWithSalt h (PDelay fc d t p)
        = h `hashWithSalt` 5 `hashWithSalt` d `hashWithSalt` t `hashWithSalt` p
    hashWithSalt h (PLoc fc x)
        = h `hashWithSalt` 6 `hashWithSalt` x
    hashWithSalt h (PUnmatchable fc x)
        = h `hashWithSalt` 7 `hashWithSalt` x

  export
  Hashable (CaseTree vars) where
    hashWithSalt h (Case idx x scTy xs)
        = h `hashWithSalt` 0 `hashWithSalt` idx `hashWithSalt` xs
    hashWithSalt h (STerm _ x)
        = h `hashWithSalt` 1 `hashWithSalt` x
    hashWithSalt h (Unmatched msg)
        = h `hashWithSalt` 2
    hashWithSalt h Impossible
        = h `hashWithSalt` 3

  export
  Hashable (CaseAlt vars) where
    hashWithSalt h (ConCase x tag args y)
        = h `hashWithSalt` 0 `hashWithSalt` x `hashWithSalt` args
            `hashWithSalt` y
    hashWithSalt h (DelayCase t x y)
        = h `hashWithSalt` 2 `hashWithSalt` (show t)
            `hashWithSalt` (show x) `hashWithSalt` y
    hashWithSalt h (ConstCase x y)
        = h `hashWithSalt` 3 `hashWithSalt` (show x) `hashWithSalt` y
    hashWithSalt h (DefaultCase x)
        = h `hashWithSalt` 4 `hashWithSalt` x

export
Hashable PrimType where
  hashWithSalt h = \case
    IntType     => h `hashWithSalt` 1
    Int8Type    => h `hashWithSalt` 2
    Int16Type   => h `hashWithSalt` 3
    Int32Type   => h `hashWithSalt` 4
    Int64Type   => h `hashWithSalt` 5
    IntegerType => h `hashWithSalt` 6
    Bits8Type   => h `hashWithSalt` 7
    Bits16Type  => h `hashWithSalt` 8
    Bits32Type  => h `hashWithSalt` 9
    Bits64Type  => h `hashWithSalt` 10
    StringType  => h `hashWithSalt` 11
    CharType    => h `hashWithSalt` 12
    DoubleType  => h `hashWithSalt` 13
    WorldType   => h `hashWithSalt` 14

export
Hashable Constant where
  hashWithSalt h = \case
    I i   => h `hashWithSalt` 0  `hashWithSalt` i
    I8 x  => h `hashWithSalt` 1  `hashWithSalt` x
    I16 x => h `hashWithSalt` 2  `hashWithSalt` x
    I32 x => h `hashWithSalt` 3  `hashWithSalt` x
    I64 x => h `hashWithSalt` 4  `hashWithSalt` x
    BI x  => h `hashWithSalt` 5  `hashWithSalt` x
    B8 x  => h `hashWithSalt` 6  `hashWithSalt` x
    B16 x => h `hashWithSalt` 7  `hashWithSalt` x
    B32 x => h `hashWithSalt` 8  `hashWithSalt` x
    B64 x => h `hashWithSalt` 9  `hashWithSalt` x
    Str x => h `hashWithSalt` 10 `hashWithSalt` x
    Ch x  => h `hashWithSalt` 11 `hashWithSalt` x
    Db x  => h `hashWithSalt` 12 `hashWithSalt` x
    PrT x => h `hashWithSalt` 13 `hashWithSalt` x

    WorldVal => h `hashWithSalt` 14
