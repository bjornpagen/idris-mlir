-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
||| Recognisers of tokens, and what one reads.
|||
||| A recogniser gives no value, only whether it matched and how much it
||| read, so it is data: every constructor's fields have types it fixes,
||| the consumption indices aside, which are erased. Being data, a
||| recogniser may name itself after a character it reads (`andThen`), and
||| the scan that runs it recurses on its structure, and on the characters
||| left once one is read.
module Libraries.Text.Lexer.Core

import Control.WellFounded
import Data.Nat

import public Libraries.Text.Bounded
import Libraries.Text.Progress

%default total

||| A language of token recognisers.
||| @ consumes If `True`, every match reads at least one character.
export
data Recognise : (consumes : Bool) -> Type where
     Empty : Recognise False
     Fail : Recognise c
     EOF : Recognise False
     Expect : Recognise True -> Recognise False
     Reject : Recognise True -> Recognise False
     Pred : (Char -> Bool) -> Recognise True
     SeqEat : Recognise True -> Inf (Recognise e) -> Recognise True
     SeqEmpty : Recognise e1 -> Recognise e2 -> Recognise (e1 || e2)
     Alt : Recognise e1 -> Recognise e2 -> Recognise (e1 && e2)

||| A token recogniser: every match reads at least one character.
public export
Lexer : Type
Lexer = Recognise True

||| Two recognisers in sequence. The sequence consumes if either does.
export %inline
(<+>) : Recognise c1 -> Recognise c2 -> Recognise (c1 || c2)
(<+>) = SeqEmpty

export infixl 8 `andThen`

||| A recogniser that reads a character, then one made only once it has
||| matched, which may therefore be the recogniser being defined.
export %inline
andThen : Lexer -> Inf (Recognise c) -> Lexer
andThen = SeqEat

||| Two alternative recognisers, the first that matches. If both consume,
||| so does the choice.
export %inline
(<|>) : Recognise c1 -> Recognise c2 -> Recognise (c1 && c2)
(<|>) = Alt

||| A recogniser that never matches.
export %inline
fail : Recognise c
fail = Fail

||| A match of no input.
export %inline
empty : Recognise False
empty = Empty

||| A match at the end of the input.
export %inline
eof : Recognise False
eof = EOF

||| A character the predicate holds of.
export %inline
pred : (Char -> Bool) -> Lexer
pred = Pred

||| A match of no input where the lexer would match.
export %inline
expect : Lexer -> Recognise False
expect = Expect

||| A match of no input where the lexer would not match.
export %inline
reject : Lexer -> Recognise False
reject = Reject

||| What a recogniser read of its input: how many characters, and the input
||| after them, by its type no longer, and shorter if it consumes.
public export
data Scanned : (consumes : Bool) -> (input : List Char) -> Type where
  MkScanned : (width : Nat) -> (remaining : List Char) ->
              (0 shorter : Leaves consumes (List.length remaining) (List.length input)) ->
              Scanned consumes input

-- What a recogniser read after another that read `n`, as read from where
-- the first began.
following : (0 c1, c2 : Bool) -> (n : Nat) ->
            (0 first : Leaves c1 (List.length middle) (List.length input)) ->
            Maybe (Scanned c2 middle) -> Maybe (Scanned (c1 || c2) input)
following c1 c2 n first Nothing = Nothing
following c1 c2 n first (Just (MkScanned m rest second))
    = Just (MkScanned (n + m) rest (inSequence c1 c2 first second))

-- What the second of two alternatives read.
secondRead : (0 c1, c2 : Bool) -> Maybe (Scanned c2 input) -> Maybe (Scanned (c1 && c2) input)
secondRead c1 c2 Nothing = Nothing
secondRead c1 c2 (Just (MkScanned n rest fewer)) = Just (MkScanned n rest (secondOf c1 c2 fewer))

-- A recogniser run on its own structure, but the recogniser after one that
-- consumed (`SeqEat`) is made by forcing it, no part of the recogniser
-- given: that recursion is on the characters left, which are accessible
-- (`acc`), bounded by `bound` until a recogniser consumes.
scanFrom : (r : Recognise c) -> (input : List Char) ->
           (0 acc : Accessible Nat.LT bound) -> (0 below : Nat.LTE (List.length input) bound) ->
           Maybe (Scanned c input)
scanFrom Empty input acc below = Just (MkScanned 0 input reflexive)
scanFrom Fail input acc below = Nothing
scanFrom EOF [] acc below = Just (MkScanned 0 [] reflexive)
scanFrom EOF (_ :: _) acc below = Nothing
scanFrom (Expect r) input acc below
    = case scanFrom r input acc below of
           Just _ => Just (MkScanned 0 input reflexive)
           Nothing => Nothing
scanFrom (Reject r) input acc below
    = case scanFrom r input acc below of
           Just _ => Nothing
           Nothing => Just (MkScanned 0 input reflexive)
scanFrom (Pred f) [] acc below = Nothing
scanFrom (Pred f) (x :: xs) acc below
    = if f x then Just (MkScanned 1 xs reflexive) else Nothing
scanFrom (SeqEat {e} r1 r2) input acc@(Access rec) below
    = case scanFrom r1 input acc below of
           Nothing => Nothing
           Just (MkScanned n rest fewer) =>
             following True e n fewer
               (scanFrom r2 rest (rec (List.length rest) (transitive fewer below)) reflexive)
scanFrom (SeqEmpty {e1} {e2} r1 r2) input acc below
    = case scanFrom r1 input acc below of
           Nothing => Nothing
           Just (MkScanned n rest fewer) =>
             following e1 e2 n fewer (scanFrom r2 rest acc (transitive (noMore e1 fewer) below))
scanFrom (Alt {e1} {e2} r1 r2) input acc below
    = case scanFrom r1 input acc below of
           Just (MkScanned n rest fewer) => Just (MkScanned n rest (firstOf e1 e2 fewer))
           Nothing => secondRead e1 e2 (scanFrom r2 input acc below)

||| What the recogniser reads at the start of the input, or nothing where
||| it does not match.
export
scan : (r : Recognise c) -> (input : List Char) -> Maybe (Scanned c input)
scan r input = scanFrom r input (wellFounded (List.length input)) reflexive
