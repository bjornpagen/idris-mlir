-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Core.Binary.Prims

import Core.Context.Context
import Core.Core
import Core.Primitives.Host

import Control.Relation
import Control.WellFounded
import Data.Buffer
import Data.DPair
import Data.List.Elem
import Data.List1
import Data.Nat
import Data.So
import Data.String
import Data.Vect

import Libraries.Data.NatSet
import public Libraries.Utils.Binary
import public Libraries.Utils.String
import Libraries.Data.WithDefault

import System.File

-- A label for binary states
export
data Bin : Type where

-- A label for storing resolved name ids
export
data ResID : Type where

public export
interface TTC a where -- TTC = TT intermediate code/interface file
  -- Add binary data representing the value to the given buffer
  toBuf : Ref Bin Binary => a -> Core ()
  -- Return the data representing a thing of type 'a' from the given buffer.
  -- Throws if the data can't be parsed as an 'a'. An identifier read back
  -- is interned in the session's table: a TTC holds identifiers as text,
  -- written from content, never as a session's ids.
  fromBuf : Ref Bin Binary => {auto ids : Ref Interned Idents} -> Core a

-- Create a new list of chunks, initialised with one 64k chunk
export
initBinary : Core (Ref Bin Binary)
initBinary
    = do Just buf <- coreLift $ newBuffer blockSize
             | Nothing => throw (InternalError "Buffer creation failed")
         newRef Bin (newBinary buf (cast blockSize))

export
initBinaryS : Int -> Core (Ref Bin Binary)
initBinaryS s
    = do Just buf <- coreLift $ newBuffer s
             | Nothing => throw (InternalError "Buffer creation failed")
         newRef Bin (newBinary buf (cast s))

extendBinary : Integer -> Binary -> Core Binary
extendBinary need (MkBin buf l s u)
    = do let newsize = s * 2
         let s' = if (newsize - l) < need
                     then newsize + need
                     else newsize
         Just buf' <- coreLift $ resizeBuffer buf (cast s')
             | Nothing => throw (InternalError "Buffer expansion failed")
         pure (MkBin buf' l s' u)

export
corrupt : String -> Core a
corrupt ty = throw (TTCError (Corrupt ty))

-- tag and getTag assume the Int is in the range 0-255 (we don't have
-- Bits8 yet!)
export
tag : {auto b : Ref Bin Binary} -> Int -> Core ()
tag {b} val
    = do chunk <- get Bin
         if avail chunk >= 1
            then
              do coreLift $ setBits8 (buf chunk) (cast $ loc chunk) $ cast val
                 put Bin (appended 1 chunk)
            else do chunk' <- extendBinary 1 chunk
                    coreLift $ setBits8 (buf chunk') (cast $ loc chunk') $ cast val
                    put Bin (appended 1 chunk')

export
getTag : {auto b : Ref Bin Binary} -> Core Int
getTag {b}
    = do chunk <- get Bin
         if toRead chunk >= 1
            then
              do val <- coreLift $ getBits8 (buf chunk) (cast $ loc chunk)
                 put Bin (incLoc 1 chunk)
                 pure $ cast val
              else throw (TTCError (EndOfBuffer "Bits8"))

||| The bytes a decoder has left to read. A decoder of a value that holds
||| others reads its tag before it decodes one of them, so the bytes left
||| are fewer at each part it decodes: they are the measure its recursion
||| descends.
export total
remaining : {auto b : Ref Bin Binary} -> Core Nat
remaining = do chunk <- get Bin
               pure (integerToNat (toRead chunk))

||| The bytes left now, with the proof that they are fewer than `n`, those
||| left when the asking decoder began. It asks once it has read its tag, so
||| they are fewer for every buffer a decoder wrote. The decision is one
||| comparison of the two counts and the proof is erased, never built, so a
||| part costs the same however many bytes follow it.
export total
fewer : {auto b : Ref Bin Binary} -> (n : Nat) -> Core (Subset Nat (\m => LT m n))
fewer n
    = do m <- remaining
         case choose (m < n) of
              Left lt => pure (Element m (ltOpReflectsLT m n lt))
              Right _ => corrupt "TTC: a part that reads nothing"

-- Primitives; these are the only things that have to deal with growing
-- the buffer list

-- Some useful types from the prelude

export
[Wasteful] TTC Int where
  toBuf val
    = do chunk <- get Bin
         if avail chunk >= 8
            then
              do coreLift $ setInt (buf chunk) (cast $ loc chunk) val
                 put Bin (appended 8 chunk)
            else do chunk' <- extendBinary 8 chunk
                    coreLift $ setInt (buf chunk') (cast $ loc chunk') val
                    put Bin (appended 8 chunk')

  fromBuf
    = do chunk <- get Bin
         if toRead chunk >= 8
            then
              do val <- coreLift $ getInt (buf chunk) (cast $ loc chunk)
                 put Bin (incLoc 8 chunk)
                 pure val
              else throw (TTCError (EndOfBuffer ("Int " ++ show (loc chunk, Binary.size chunk))))

export
TTC Int where
  toBuf val
    = if val >= -127 && val < 128
         then tag (val + 127)
         else do tag 255
                 chunk <- get Bin
                 if avail chunk >= 8
                    then
                      do coreLift $ setInt (buf chunk) (cast $ loc chunk) val
                         put Bin (appended 8 chunk)
                    else do chunk' <- extendBinary 8 chunk
                            coreLift $ setInt (buf chunk') (cast $ loc chunk') val
                            put Bin (appended 8 chunk')

  fromBuf
    = case !getTag of
           255 => do chunk <- get Bin
                     if toRead chunk >= 8
                       then
                         do val <- coreLift $ getInt (buf chunk) (cast $ loc chunk)
                            put Bin (incLoc 8 chunk)
                            pure val
                       else throw (TTCError (EndOfBuffer ("Int " ++ show (loc chunk, Binary.size chunk))))
           t => pure (t - 127)

export
TTC String where
  toBuf val
      -- To support UTF-8 strings, this has to get the length of the string
      -- in bytes, not the length in characters.
      = do let ireq = stringByteLength val
           let req : Integer = cast ireq
           toBuf ireq
           chunk <- get Bin
           if avail chunk >= req
              then
                do coreLift $ setString (buf chunk) (cast $ loc chunk) val
                   put Bin (appended req chunk)
              else do chunk' <- extendBinary req chunk
                      coreLift $ setString (buf chunk') (cast $ loc chunk') val
                      put Bin (appended req chunk')

  fromBuf
      = do ilen <- fromBuf {a = Int}
           chunk <- get Bin
           let len = cast ilen
           when (len < 0) $ corrupt "String"
           if toRead chunk >= len
              then
                do val <- coreLift $ getString (buf chunk) (cast $ loc chunk) ilen
                   put Bin (incLoc len chunk)
                   pure val
              else throw (TTCError (EndOfBuffer ("String length " ++ show len ++
                                                 " at " ++ show (loc chunk))))

||| An identifier is written as its text and read back by interning it.
export
TTC Ident where
  toBuf i = toBuf i.text

  fromBuf
      = do s <- fromBuf {a = String}
           t <- get Interned
           let (i, t') = internIn s t
           put Interned t'
           pure i

export
TTC Binary where
  toBuf val
    = do let len = used val
         let ilen : Int = cast len
         toBuf ilen
         chunk <- get Bin
         if avail chunk >= len
            then
              do coreLift $ copyData (buf val) 0 ilen
                                     (buf chunk) (cast $ loc chunk)
                 put Bin (appended len chunk)
            else do chunk' <- extendBinary len chunk
                    coreLift $ copyData (buf val) 0 ilen
                                        (buf chunk') (cast $ loc chunk')
                    put Bin (appended len chunk')

  fromBuf
    = do ilen <- fromBuf
         let len : Integer = cast ilen
         chunk <- get Bin
         if toRead chunk >= len
            then
              do Just newbuf <- coreLift $ newBuffer ilen
                      | Nothing => corrupt "Binary"
                 coreLift $ copyData (buf chunk) (cast $ loc chunk) ilen
                                     newbuf 0
                 put Bin (incLoc len chunk)
                 pure (MkBin newbuf 0 len len)
            else throw (TTCError (EndOfBuffer "Binary"))

export
TTC Bool where
  toBuf False = tag 0
  toBuf True = tag 1
  fromBuf
      = case !getTag of
             0 => pure False
             1 => pure True
             _ => corrupt "Bool"

export
TTC Char where
  toBuf c = toBuf (cast {to=Int} c)
  fromBuf
      = do i <- fromBuf
           pure (cast {from=Int} i)

export
TTC Double where
  toBuf val
    = do chunk <- get Bin
         if avail chunk >= 8
            then
              do coreLift $ setDouble (buf chunk) (cast $ loc chunk) val
                 put Bin (appended 8 chunk)
            else do chunk' <- extendBinary 8 chunk
                    coreLift $ setDouble (buf chunk') (cast $ loc chunk') val
                    put Bin (appended 8 chunk')

  fromBuf
    = do chunk <- get Bin
         if toRead chunk >= 8
            then
              do val <- coreLift $ getDouble (buf chunk) (cast $ loc chunk)
                 put Bin (incLoc 8 chunk)
                 pure val
              else throw (TTCError (EndOfBuffer "Double"))

export
(TTC a, TTC b) => TTC (a, b) where
  toBuf (x, y)
     = do toBuf x
          toBuf y
  fromBuf
     = do x <- fromBuf
          y <- fromBuf
          pure (x, y)

export
TTC () where
  toBuf () = pure ()
  fromBuf = pure ()

export
(TTC a, {y : a} -> TTC (p y)) => TTC (DPair a p) where
  toBuf (vs ** tm)
      = do toBuf vs
           toBuf tm

  fromBuf
      = do x <- fromBuf
           p <- fromBuf
           pure (x ** p)

export
TTC a => TTC (Maybe a) where
  toBuf Nothing
     = tag 0
  toBuf (Just val)
     = do tag 1
          toBuf val

  fromBuf
     = case !getTag of
            0 => pure Nothing
            1 => do val <- fromBuf
                    pure (Just val)
            _ => corrupt "Maybe"

export
TTC a => TTC (WithDefault a def) where
  toBuf def = onWithDefault
                  (tag 0)
                  (\v => do tag 1
                            toBuf v)
                  def

  fromBuf
     = case !getTag of
            0 => pure defaulted
            1 => do val <- fromBuf
                    pure (specified val)
            _ => corrupt "WithDefault"

export
(TTC a, TTC b) => TTC (Either a b) where
  toBuf (Left val)
     = do tag 0
          toBuf val
  toBuf (Right val)
     = do tag 1
          toBuf val

  fromBuf
     = case !getTag of
            0 => do val <- fromBuf
                    pure (Left val)
            1 => do val <- fromBuf
                    pure (Right val)
            _ => corrupt "Either"

export
TTC a => TTC (List a) where
  toBuf xs
      = do toBuf (TailRec_length xs)
           traverse_ (toBuf) xs
    where
      ||| Tail-recursive length as buffer sizes can get large
      |||
      ||| Once we port to Idris2, can use Data.List.TailRec.length instead
      length_aux : List a -> Int -> Int
      length_aux [] len = len
      length_aux (_::xs) len = length_aux xs (1 + len)

      TailRec_length : List a -> Int
      TailRec_length xs = length_aux xs 0

  fromBuf
      = do len <- fromBuf {a = Int}
           readElems [] (integerToNat (cast len))
    where
      readElems : List a -> Nat -> Core (List a)
      readElems xs Z = pure (reverse xs)
      readElems xs (S k)
          = do val <- fromBuf
               readElems (val :: xs) k

export
TTC a => TTC (List1 a) where
  toBuf xxs
     = do toBuf (head xxs)
          toBuf (tail xxs)

  fromBuf = do
    x <- fromBuf
    xs <- fromBuf
    pure (x ::: xs)

export
{n : Nat} -> TTC a => TTC (Vect n a) where
  toBuf xs = writeAll xs
    where
      writeAll : forall n . Vect n a -> Core ()
      writeAll [] = pure ()
      writeAll (x :: xs) = do toBuf x; writeAll xs

  fromBuf {n} = rewrite sym (plusZeroRightNeutral n) in readElems [] n
    where
      readElems : Vect done a -> (todo : Nat) -> Core (Vect (todo + done) a)
      readElems {done} xs Z
          = pure (reverse xs)
      readElems {done} xs (S k)
          = do val <- fromBuf
               rewrite (plusSuccRightSucc k done)
               readElems (val :: xs) k

%hide Fin.fromInteger

count : List.Elem.Elem x xs -> Int
count Here = 0
count (There p) = 1 + count p

-- An integer is written as its sign and its magnitude's limbs: 32 bits
-- each, least significant first, the last never zero, so zero has none.
-- There is a limb at every place whose weight, 2^(32 * place), is at most
-- the magnitude; the limb is the magnitude shifted right by that place's
-- bits and cut to 32 of them. The places end by Nat's arithmetic, whatever
-- the host's shifts give: each weight is the one before it times 2^32
-- (`Core.Primitives.Host.limbBase`, held by name so that no type here holds
-- it in unary), so the room the weights leave below the magnitude shrinks
-- at every place (`roomShrinks`), and the recursion is on that room's
-- accessibility, erased. The machine compares a weight with the magnitude
-- by `compareNat`, which both hosts run on integers.

-- Where a weight stands against the magnitude, by the machine's comparison:
-- past it, or within it, with the evidence.
data Placed : Nat -> Nat -> Type where
  Past : Placed w m
  Within : (0 _ : Nat.LTE w m) -> Placed w m

0 ltNotGT : EqOrd.LT = EqOrd.GT -> Void
ltNotGT Refl impossible

0 eqNotGT : EqOrd.EQ = EqOrd.GT -> Void
eqNotGT Refl impossible

-- A weight the comparison does not put past the magnitude is within it.
0 notPast : (w, m : Nat) -> Not (compareNat w m = EqOrd.GT) -> Nat.LTE w m
notPast Z m _ = LTEZero
notPast (S w) Z past = absurd (past Refl)
notPast (S w) (S m) past = LTESucc (notPast w m past)

placed : (w, m : Nat) -> Placed w m
placed w m with (compareNat w m) proof cmp
  _ | EqOrd.GT = Past
  _ | EqOrd.LT = Within (notPast w m (\past => ltNotGT (trans (sym cmp) past)))
  _ | EqOrd.EQ = Within (notPast w m (\past => eqNotGT (trans (sym cmp) past)))

-- Taking off at most a weight leaves at least as much.
0 minusSelf : (n, c : Nat) -> Nat.LTE (minus n c) n
minusSelf Z c = LTEZero
minusSelf (S n) Z = reflexive
minusSelf (S n) (S c) = lteSuccRight (minusSelf n c)

0 minusAntitone : (n : Nat) -> Nat.LTE a c -> Nat.LTE (minus n c) (minus n a)
minusAntitone n (LTEZero {right = c}) = rewrite minusZeroRight n in minusSelf n c
minusAntitone Z (LTESucc _) = LTEZero
minusAntitone (S n) (LTESucc le) = minusAntitone n le

-- What a magnitude leaves past a weight within it, one more.
0 minusSucc : Nat.LTE w m -> minus (S m) w = S (minus m w)
minusSucc (LTEZero {right = m}) = rewrite minusZeroRight m in Refl
minusSucc (LTESucc le) = minusSucc le

-- A natural is at most itself times a positive one.
0 selfBelowTimes : (w : Nat) -> Nat.LTE 1 b -> Nat.LTE w (w * b)
selfBelowTimes Z _ = LTEZero
selfBelowTimes (S w) one = plusLteMonotone one (selfBelowTimes w one)

-- A positive weight times at least two is past it.
0 pastItself : (w : Nat) -> Nat.LTE 1 w -> Nat.LTE 2 b -> Nat.LTE (S w) (w * b)
pastItself Z one _ = void (succNotLTEzero one)
pastItself (S w) _ two = plusLteMonotone two (selfBelowTimes w (lteSuccLeft two))

0 roomShrinks : {m, w, b : Nat} -> Nat.LTE 1 w -> Nat.LTE 2 b -> Nat.LTE w m -> Nat.LT (minus (S m) (w * b)) (minus (S m) w)
roomShrinks one two within =
  rewrite minusSucc within in LTESucc (minusAntitone (S m) (pastItself w one two))

0 weightPositive : {w, b : Nat} -> Nat.LTE 1 w -> Nat.LTE 2 b -> Nat.LTE 1 (w * b)
weightPositive one two = transitive (LTESucc LTEZero) (pastItself w one two)

total
limbsFrom : (m : Nat) -> (w : Nat) -> (shift : Integer) -> (0 _ : Nat.LTE 1 w) ->
            (0 _ : Accessible Nat.LT (minus (S m) w)) -> List Int
limbsFrom m w shift one (Access rec) = case placed w m of
  Past => []
  Within within =>
    fromInteger (prim__and_Integer (prim__shr_Integer (natToInteger m) shift) 0xffffffff) ::
    limbsFrom m (w * limbBase) (shift + 32) (weightPositive one limbBaseAbove)
              (rec _ (roomShrinks one limbBaseAbove within))

-- A magnitude's limbs, from the place whose weight is one.
toLimbs : Nat -> List Int
toLimbs m = limbsFrom m 1 0 (LTESucc LTEZero) (wellFounded _)

fromLimbs : List Int -> Integer
fromLimbs [] = 0
fromLimbs (x :: xs) = cast x + prim__shl_Integer (fromLimbs xs) 32

export
TTC Integer where
  toBuf val
    = if val < 0
         then do tag 0
                 toBuf (toLimbs (integerToNat (-val)))
         else do tag 1
                 toBuf (toLimbs (integerToNat val))
  fromBuf
    = do val <- getTag
         case val of
              0 => do val <- fromBuf
                      pure (-(fromLimbs val))
              1 => do val <- fromBuf
                      pure (fromLimbs val)
              _ => corrupt "Integer"

export
TTC Bits8 where
  toBuf x = toBuf $ cast {to = Int} x
  fromBuf = cast {from = Int} <$> fromBuf

export
TTC Bits16 where
  toBuf x = toBuf $ cast {to = Int} x
  fromBuf = cast {from = Int} <$> fromBuf

export
TTC Bits32 where
  toBuf x = toBuf $ cast {to = Integer} x
  fromBuf = cast {from = Integer} <$> fromBuf

export
TTC Bits64 where
  toBuf x = toBuf $ cast {to = Integer} x
  fromBuf = cast {from = Integer} <$> fromBuf

export
TTC Int8 where
  toBuf x = toBuf $ cast {to = Int} x
  fromBuf = cast {from = Int} <$> fromBuf

export
TTC Int16 where
  toBuf x = toBuf $ cast {to = Int} x
  fromBuf = cast {from = Int} <$> fromBuf

export
TTC Int32 where
  toBuf x = toBuf $ cast {to = Int} x
  fromBuf = cast {from = Int} <$> fromBuf

export
TTC Int64 where
  toBuf x = toBuf $ cast {to = Integer} x
  fromBuf = cast {from = Integer} <$> fromBuf

export
TTC Nat where
  toBuf val = toBuf (cast {to=Integer} val)
  fromBuf
     = do val <- fromBuf
          pure (fromInteger val)

-- A set is written as its words, each of which has no sign, so whatever
-- bytes are read give a set; written as an integer, a set could be read
-- back negative.
export
TTC NatSet where
  toBuf ns = toBuf (NatSet.toWords ns)
  fromBuf = NatSet.fromWords <$> fromBuf

||| Get a file's modified time. If it doesn't exist, return 0 (UNIX Epoch)
export
modTime : String -> Core Timestamp
modTime fname
  = do Right f <- coreLift $ openFile fname Read
         | Left err => pure $ MkTimestamp 0 0 -- Beginning of Time :)
       Right t <- coreLift $ fileTime f
         | Left err => do coreLift $ closeFile f
                          pure $ MkTimestamp 0 0
       coreLift $ closeFile f
       pure $ t.mtime

export
TTC a => TTC (SnocList a) where
  toBuf xs
      = do toBuf (TailRec_length xs)
           traverse_ toBuf xs
    where
      ||| Tail-recursive length as buffer sizes can get large
      |||
      ||| Once we port to Idris2, can use Data.List.TailRec.length instead
      length_aux : SnocList a -> Int -> Int
      length_aux [<] len = len
      length_aux (xs :< _) len = length_aux xs (1 + len)

      TailRec_length : SnocList a -> Int
      TailRec_length xs = length_aux xs 0

  fromBuf
      = do len <- fromBuf {a = Int}
           readElems [<] (integerToNat (cast len))
    where
      readElems : SnocList a -> Nat -> Core (SnocList a)
      readElems xs Z = pure (reverse xs)
      readElems xs (S k)
          = do val <- fromBuf
               readElems (xs :< val) k
