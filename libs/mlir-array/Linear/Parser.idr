-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Parsers over a handle to immutable bytes.
|||
||| A parser takes the handle at quantity 1 and an offset, a word, and gives
||| the handle back whether it succeeds or fails: so `<|>` runs its second
||| parser on the same handle from the same offset, saving one word, and
||| nothing is copied for backtracking. A parser reads bytes and never writes
||| them, so its reads order with nothing. What a token read is, is a `Span`
||| of the handle: two offsets, not a string.
|||
||| The furthest offset any alternative failed at travels through every
||| parser as an argument, so a failure reports where the input went wrong
||| without a merge after each step: a parser after `>>=` and the second
||| parser of `<|>` are tail calls.
module Linear.Parser

import public Linear.Bytes
import Control.WellFounded
import Data.Nat
import Data.So

%default total

------------------------------------------------------------------------------
-- Results and parsers
------------------------------------------------------------------------------

||| What a parser gives: the handle back, always, with the furthest offset
||| a failure was seen at; on success, also the offset after what it read
||| and its value.
public export
data Result : (0 r : Type) -> (0 n : Nat) -> Type -> Type where
  Ok : (1 input : Bytes r n) -> (to : Nat) -> (0 within : LTE to n) -> (furthest : Nat) -> (val : a) ->
       Result r n a
  Fail : (1 input : Bytes r n) -> (furthest : Nat) -> Result r n a

||| A parser of the bytes of region `r`: from an offset within them, and the
||| furthest failure so far, a result.
public export
Parser : (0 r : Type) -> (0 n : Nat) -> Type -> Type
Parser r n a = (1 input : Bytes r n) -> (from : Nat) -> (0 within : LTE from n) -> (furthest : Nat) -> Result r n a

||| The later of the furthest failure so far and a failure at `at`.
furthestOf : Nat -> Nat -> Nat
furthestOf far at = if far < at then at else far

------------------------------------------------------------------------------
-- What a lexer and a parser are made of
------------------------------------------------------------------------------

continue : (a -> Parser r n b) -> (1 _ : Result r n a) -> Result r n b
continue f (Ok input to within far x) = f x input to within far
continue f (Fail input far) = Fail input far

convert : (a -> b) -> (1 _ : Result r n a) -> Result r n b
convert f (Ok input to within far x) = Ok input to within far (f x)
convert f (Fail input far) = Fail input far

retry : Parser r n a -> (from : Nat) -> (0 _ : LTE from n) -> (1 _ : Result r n a) -> Result r n a
retry q from within (Ok input to w far x) = Ok input to w far x
retry q from within (Fail input far) = q input from within far

-- The names a parser shares with the Prelude's interfaces live in their own
-- namespace, so that `do` and `<|>` over parsers read as they do over any
-- monad; nothing in this module calls them, so nothing here resolves one.
namespace Parser
  ||| Success, reading nothing.
  export
  pure : a -> Parser r n a
  pure x = \input, from, within, far => Ok input from within far x

  ||| Failure, at the offset it starts at.
  export
  fail : Parser r n a
  fail = \input, from, within, far => Fail input (furthestOf far from)

  ||| `p`, then the parser its value chooses, from where `p` stopped.
  export
  (>>=) : Parser r n a -> (a -> Parser r n b) -> Parser r n b
  p >>= f = \input, from, within, far => continue f (p input from within far)

  ||| `p`, then `q`, keeping `q`'s value.
  export
  (>>) : Parser r n () -> Parser r n b -> Parser r n b
  p >> q = \input, from, within, far => continue (\_ => q) (p input from within far)

  ||| `p`'s value under `f`.
  export
  map : (a -> b) -> Parser r n a -> Parser r n b
  map f p = \input, from, within, far => convert f (p input from within far)

  ||| `p`, or, where `p` fails, `q` from the same offset on the handle `p`
  ||| gave back.
  export
  (<|>) : Parser r n a -> Parser r n a -> Parser r n a
  p <|> q = \input, from, within, far => retry q from within (p input from within far)

check : (Bits8 -> Bool) -> (from : Nat) -> (far : Nat) -> (1 _ : Peeked r n from) -> Result r n Bits8
check ok from far (Byte input b more) = if ok b then Ok input (S from) more far b else Fail input (furthestOf far from)
check ok from far (End input) = Fail input (furthestOf far from)

||| The byte at the offset, where `ok` holds of it.
export
satisfy : (Bits8 -> Bool) -> Parser r n Bits8
satisfy ok = \input, from, within, far => check ok from far (peek input from)

||| This byte.
export
byte : Bits8 -> Parser r n Bits8
byte b = satisfy (== b)

atEnd : (from : Nat) -> (0 _ : LTE from n) -> (far : Nat) -> (1 _ : Peeked r n from) -> Result r n ()
atEnd from within far (End input) = Ok input from within far ()
atEnd from within far (Byte input _ _) = Fail input (furthestOf far from)

||| The end of the bytes.
export
eof : Parser r n ()
eof = \input, from, within, far => atEnd from within far (peek input from)

mutual
  spellFrom : List Bits8 -> (1 input : Bytes r n) -> (at : Nat) -> (0 _ : LTE at n) -> (far : Nat) -> Result r n ()
  spellFrom [] input at within far = Ok input at within far ()
  spellFrom (b :: bs) input at within far = spellNext b bs at far (peek input at)

  spellNext : Bits8 -> List Bits8 -> (at : Nat) -> (far : Nat) -> (1 _ : Peeked r n at) -> Result r n ()
  spellNext b bs at far (Byte input c more) =
    if c == b then spellFrom bs input (S at) more far else Fail input (furthestOf far at)
  spellNext b bs at far (End input) = Fail input (furthestOf far at)

||| These bytes, in order.
export
literal : List Bits8 -> Parser r n ()
literal bs = \input, from, within, far => spellFrom bs input from within far

spanFrom : (from : Nat) -> (1 _ : Result r n a) -> Result r n (Span r n)
spanFrom from (Ok input to within far _) = Ok input to within far (MkSpan from to within)
spanFrom from (Fail input far) = Fail input far

||| What `p` read, as a view of the input; `p`'s value dropped.
export
spanOf : Parser r n a -> Parser r n (Span r n)
spanOf p = \input, from, within, far => spanFrom from (p input from within far)

------------------------------------------------------------------------------
-- Repetition
------------------------------------------------------------------------------

||| What is left of a count once some of it is taken is no more than it.
0 minusLeft : (l, k : Nat) -> LTE (minus l k) l
minusLeft Z _ = LTEZero
minusLeft (S l) Z = reflexive
minusLeft (S l) (S k) = lteSuccRight (minusLeft l k)

||| Moving forward within the bytes leaves fewer of them.
0 shrink : (n : Nat) -> {from, to : Nat} -> LT from to -> LTE to n -> LT (minus n to) (minus n from)
shrink Z (LTESucc _) fits = absurd fits
shrink (S k) {from = Z} {to = S t} (LTESucc _) (LTESucc _) = LTESucc (minusLeft k t)
shrink (S k) {from = S f} {to = S t} (LTESucc moved) (LTESucc fits) = shrink k moved fits

-- A loop over the input ends because each round moves forward, which a
-- comparison the round makes anyway decides, its evidence erased: the
-- bytes left after it are fewer, so the recursion is on what is left.

repeatFrom : Parser r n a -> SnocList a -> (1 input : Bytes r n) -> (at : Nat) -> (0 within : LTE at n) ->
             (far : Nat) -> (0 _ : Accessible LT (minus n at)) -> Result r n (List a)
repeatFrom p acc input at within far (Access rec) = case p input at within far of
  Ok input' to fits far' x => case choose (at < to) of
    Left moved =>
      repeatFrom p (acc :< x) input' to fits far' (rec (minus n to) (shrink n (ltOpReflectsLT at to moved) fits))
    Right _ => Ok input' to fits far' (acc <>> [x])
  Fail input' far' => Ok input' at within far' (acc <>> [])

||| `p` as many times as it succeeds, and none at least. A success that
||| reads nothing is the last: it cannot be told from the next.
export
many : Parser r n a -> Parser r n (List a)
many p = \input, from, within, far => repeatFrom p [<] input from within far (wellFounded (minus n from))

||| `p` at least once.
export
some : Parser r n a -> Parser r n (List a)
some p = \input, from, within, far => continue moreOf (p input from within far)
  where
    moreOf : a -> Parser r n (List a)
    moreOf x = \input, from, within, far => convert (x ::) (many p input from within far)

scanFrom : (Bits8 -> Bool) -> (start : Nat) -> (1 input : Bytes r n) -> (at : Nat) -> (0 within : LTE at n) ->
           (far : Nat) -> (0 _ : Accessible LT (minus n at)) -> Result r n (Span r n)
scanFrom ok start input at within far (Access rec) = case peek input at of
  Byte input' b more =>
    if ok b
      then scanFrom ok start input' (S at) more far (rec (minus n (S at)) (shrink n {from = at} {to = S at} reflexive more))
      else Ok input' at within far (MkSpan start at within)
  End input' => Ok input' at within far (MkSpan start at within)

||| The bytes from the offset on while `ok` holds, as a view, perhaps empty:
||| one loop over the bytes, nothing built for each.
export
spanWhile : (Bits8 -> Bool) -> Parser r n (Span r n)
spanWhile ok = \input, from, within, far => scanFrom ok from input from within far (wellFounded (minus n from))

------------------------------------------------------------------------------
-- Running
------------------------------------------------------------------------------

||| How a parse ended: the offset after what it read and its value, or the
||| furthest offset any alternative failed at.
public export
data Outcome : Type -> Type where
  Parsed : (end : Nat) -> a -> Outcome a
  Stuck : (furthest : Nat) -> Outcome a

finish : (1 _ : Result r n a) -> Res (Outcome a) (const (Bytes r n))
finish (Ok input to _ _ x) = Parsed to x # input
finish (Fail input far) = Stuck far # input

||| `p` from the first byte; the handle given back.
export
parse : Parser r n a -> (1 _ : Bytes r n) -> Res (Outcome a) (const (Bytes r n))
parse p input = finish (p input 0 LTEZero 0)
