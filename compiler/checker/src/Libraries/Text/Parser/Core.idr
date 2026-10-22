-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
||| What a grammar is, what it runs on and gives back, and the combinators
||| every other is made of.
|||
||| A grammar is the parser itself: a function from where a parse stands to
||| what it gives. A sequence's intermediate result is then the type of a
||| function's argument, fixed where the sequence is written, and no
||| constructor holds a value whose type it hides; a grammar built of
||| constructors, read by one interpreter, would hide the type of every
||| value a sequence passes on, and its interpreter would run at each of
||| them. Whatever a program's grammars are, each combinator here is a
||| function at the types its use gives it.
|||
||| A parse holds its input once: the tokens, as columns, and what it has
||| made, its own state, its warnings and its commitment. Every grammar
||| takes the input at quantity 1 and gives it back, succeeding or failing,
||| with how many tokens it left, so the input is updated in place and
||| nothing of it is counted. An alternative keeps only where it began, a
||| number, and the state's mark; when a branch fails it goes back to them,
||| so a failed branch costs what it did, never a copy.
|||
||| A grammar's type bounds the tokens it may read, and says whether it runs
||| only once a token has been read since the parse stood at the bound. A
||| grammar that names another grammar, or itself, reaches it through a box:
||| what a box holds is had only at a bound below the box's, which a grammar
||| stands at once it has read a token, so every grammar a program names,
||| through every recursion between grammars, ends. One fixpoint ties a
||| grammar to the box of itself. The bound is erased, so it costs nothing at
||| run time.
module Libraries.Text.Parser.Core

import Control.WellFounded
import Data.List
import Data.List1
import Data.Nat
import Data.So

import Array

import public Libraries.Text.Bounded
import Libraries.Text.Progress
import public Libraries.Text.Trail

%default total

%hide Prelude.(>>)
%hide Prelude.(>>=)

------------------------------------------------------------------------------
-- The tokens
------------------------------------------------------------------------------

-- `n` tokens as columns: each token, and where it was read. A token's
-- position is the number of tokens after it, so the last is at 0: where a
-- parse stands is how many tokens it has left, which is what it recurses
-- on, and the next token is at that number less one, read with no
-- arithmetic.
record Columns tok (n : Nat) where
  constructor MkColumns
  vals : Vector n tok
  spans : Vector n Bounds

||| The tokens a grammar reads, as columns.
export
record Tokens tok where
  constructor MkTokens
  extent : Nat
  cols : Columns tok extent

||| A lexer's tokens as columns.
export
columns : List (Located tok) -> Tokens tok
columns toks = lastFirst (reverse toks)
  where
    value : Located tok -> tok
    value t = t.val

    place : Located tok -> Bounds
    place t = t.bounds

    lastFirst : List (Located tok) -> Tokens tok
    lastFirst ts
        = MkTokens (length ts)
                   (MkColumns (replace {p = \k => Vector k tok} (lengthMap ts) (Array.fromList (map value ts)))
                              (replace {p = \k => Vector k Bounds} (lengthMap ts) (Array.fromList (map place ts))))

-- The token with `l` tokens after it.
tokenAt : Columns tok n -> (l : Nat) -> (0 fits : Nat.LT l n) -> tok
tokenAt cols l fits = vals cols !! [<natToFinLT l {prf = fits}]

-- Where the token with `l` tokens after it was read.
boundsAt : Columns tok n -> (l : Nat) -> (0 fits : Nat.LT l n) -> Bounds
boundsAt cols l fits = spans cols !! [<natToFinLT l {prf = fits}]

-- Where the next token was read, unless no token is left.
nextBounds : Columns tok n -> (left : Nat) -> (0 fits : Nat.LTE left n) -> Maybe Bounds
nextBounds cols Z _ = Nothing
nextBounds cols (S l) fits = Just (boundsAt cols l fits)

------------------------------------------------------------------------------
-- Failures
------------------------------------------------------------------------------

||| A failure to parse: what was wanted, and where, if anywhere.
public export
data ParsingError = Error String (Maybe Bounds)

||| The warnings a parse gave, each where it was given, if anywhere.
public export
ParsingWarnings : Type
ParsingWarnings = List (Maybe Bounds, String)

-- Whether the branch an alternative is trying has passed a commit point:
-- once it has, the alternative tries no other branch.
data Commitment = Open | Committed

-- Whether a failure leaves an alternative free to try its next branch: a
-- fatal one does not, until `try` catches it.
data Severity = Recoverable | Fatal

------------------------------------------------------------------------------
-- What a parse runs on, and what a grammar gives
------------------------------------------------------------------------------

-- What a parse runs on: `n` tokens, read and never written; its own
-- state; the warnings it has given; and whether the branch it is in has
-- passed a commit point.
data Input : (state : Type) -> (tok : Type) -> (n : Nat) -> Type where
  MkInput : (cols : Columns tok n) -> (1 st : state) ->
            (1 warned : Trail (Maybe Bounds, String)) -> (com : Commitment) ->
            Input state tok n

-- What a grammar gives, from `given` tokens left: how many it left, by its
-- type no more than it was given and fewer if it consumes, the input back
-- and its value; or the input back and why it failed.
data Result : (state : Type) -> (tok : Type) -> (n : Nat) ->
              (consumes : Bool) -> (given : Nat) -> Type -> Type where
  Parsed : (left : Nat) -> (0 fewer : Leaves c left given) ->
           (1 inp : Input state tok n) -> (val : ty) -> Result state tok n c given ty
  Failed : (1 inp : Input state tok n) -> (severity : Severity) ->
           (errors : List1 ParsingError) -> Result state tok n c given ty

||| A grammar over tokens `tok`, keeping a state `state`, giving a `ty`.
||| `bound` bounds the tokens left wherever it runs, and `read` is whether
||| it runs only once a token has been read since the parse stood at the
||| bound, so below it. `consumes` is whether every success reads a token:
||| a repetition of a grammar that does recurses on the tokens it leaves,
||| which are fewer, and what follows it runs below the bound.
export
data Grammar : (state : Type) -> (tok : Type) -> (bound : Nat) -> (read : Bool) ->
               (consumes : Bool) -> (ty : Type) -> Type where
  MkGrammar : (run : {0 n : Nat} -> (left : Nat) -> (0 fits : Nat.LTE left n) ->
                     (0 under : Leaves read left bound) ->
                     (1 inp : Input state tok n) -> Result state tok n consumes left ty) ->
              Grammar state tok bound read consumes ty

%inline
run : Grammar state tok bound r c ty ->
      (left : Nat) -> (0 fits : Nat.LTE left n) -> (0 under : Leaves r left bound) ->
      (1 inp : Input state tok n) -> Result state tok n c left ty
run (MkGrammar f) left fits under inp = f left fits under inp

-- What a grammar does from a place it was given.
RunFrom : (state : Type) -> (tok : Type) -> (n : Nat) -> (consumes : Bool) -> (given : Nat) -> Type -> Type
RunFrom state tok n c given ty = (1 inp : Input state tok n) -> Result state tok n c given ty

------------------------------------------------------------------------------
-- Backtracking a parse's own state
------------------------------------------------------------------------------

||| A parse's own state, which a parse threads through every grammar once.
||| An alternative takes the state's mark before a branch and, when the
||| branch fails before a commit point, goes back to it before the next
||| branch: the state is updated in place, and going back costs what the
||| failed branch did, never a copy. `backTo m` leaves the state as it was
||| when `here` gave `m`: a step may add to the state after a mark, or
||| change what it added since, and going back undoes both.
public export
interface Backtrack mark state | state where
  ||| Where the state stands, the state given back.
  here : (1 st : state) -> Stepped state mark
  ||| The state as it stood at the mark.
  backTo : mark -> (1 st : state) -> state

||| A parse with no state of its own.
export
Backtrack () () where
  here st = MkStepped st ()
  backTo _ st = st

||| A trail stands at its length, and goes back by cutting what followed.
export
Backtrack Nat (Trail a) where
  here = measured
  backTo = cutTo

-- Where an alternative began: the state's mark, how many warnings had
-- been given, and the commitment outside it, which a parse leaving the
-- alternative takes back.
record Begun mark where
  constructor MkBegun
  stateAt : mark
  warnedAt : Nat
  outside : Commitment

-- The input opened for an alternative's first branch: marked, its branch
-- not yet committed.
marked : Columns tok n -> (1 st : Stepped state mark) ->
         (1 warned : Stepped (Trail (Maybe Bounds, String)) Nat) ->
         Commitment -> Stepped (Input state tok n) (Begun mark)
marked cols (MkStepped st at) (MkStepped warned count) com
    = MkStepped (MkInput cols st warned Open) (MkBegun at count com)

opened : Backtrack mark state => (1 inp : Input state tok n) -> Stepped (Input state tok n) (Begun mark)
opened (MkInput cols st warned com) = marked cols (here st) (measured warned) com

-- The input put back to where the alternative began, for its next branch.
reopened : Backtrack mark state =>
           Begun mark -> Columns tok n -> (1 st : state) ->
           (1 warned : Trail (Maybe Bounds, String)) -> Input state tok n
reopened b cols st warned = MkInput cols (backTo (stateAt b) st) (cutTo (warnedAt b) warned) Open

-- An input leaving the alternative, committed as it was outside it.
leaving : Begun mark -> (1 inp : Input state tok n) -> Input state tok n
leaving b (MkInput cols st warned _) = MkInput cols st warned (outside b)

-- The second branch has run. A failure past a commit point, or a fatal
-- one, is the alternative's as the branch gave it; any other is the
-- alternative's with the errors of both branches, at the commitment
-- outside it.
afterSecond : (0 c1, c2 : Bool) -> Begun mark -> List1 ParsingError ->
              (1 res : Result state tok n c2 given ty) -> Result state tok n (c1 && c2) given ty
afterSecond c1 c2 b errs (Parsed l fewer inp v) = Parsed l (secondOf c1 c2 fewer) (leaving b inp) v
afterSecond c1 c2 b errs (Failed (MkInput cols st warned Open) Recoverable errs')
    = Failed (MkInput cols st warned (outside b)) Recoverable (errs ++ errs')
afterSecond c1 c2 b errs (Failed inp severity errs') = Failed inp severity errs'

-- The first branch has run. A failure past a commit point, or a fatal one,
-- is the alternative's; any other tries the second branch from where the
-- first began.
afterFirst : Backtrack mark state =>
             (0 c1, c2 : Bool) -> Lazy (RunFrom state tok n c2 given ty) -> Begun mark ->
             (1 res : Result state tok n c1 given ty) -> Result state tok n (c1 && c2) given ty
afterFirst c1 c2 second b (Parsed l fewer inp v) = Parsed l (firstOf c1 c2 fewer) (leaving b inp) v
afterFirst c1 c2 second b (Failed (MkInput cols st warned Open) Recoverable errs)
    = afterSecond c1 c2 b errs (second (reopened b cols st warned))
afterFirst c1 c2 second b (Failed inp severity errs) = Failed (leaving b inp) severity errs

firstBranch : Backtrack mark state =>
              (0 c1, c2 : Bool) -> RunFrom state tok n c1 given ty -> Lazy (RunFrom state tok n c2 given ty) ->
              (1 at : Stepped (Input state tok n) (Begun mark)) -> Result state tok n (c1 && c2) given ty
firstBranch c1 c2 first second (MkStepped inp b) = afterFirst c1 c2 second b (first inp)

-- Two branches from one place: the first, and the second only where the
-- first fails before a commit point and not fatally.
alternative : Backtrack mark state =>
              (0 c1, c2 : Bool) -> RunFrom state tok n c1 given ty -> Lazy (RunFrom state tok n c2 given ty) ->
              RunFrom state tok n (c1 && c2) given ty
alternative c1 c2 first second inp = firstBranch c1 c2 first second (opened inp)

------------------------------------------------------------------------------
-- Sequence and choice
------------------------------------------------------------------------------

-- What followed a first grammar, from where the first began.
sequenced : (0 c1, c2 : Bool) -> (0 first : Leaves c1 middle given) ->
            (1 res : Result state tok n c2 middle ty) -> Result state tok n (c1 || c2) given ty
sequenced c1 c2 first (Parsed l second inp v) = Parsed l (inSequence c1 c2 first second) inp v
sequenced c1 c2 first (Failed inp severity errs) = Failed inp severity errs

-- The grammar a first one's value chooses, run from where the first
-- stopped: below the bound if the first read a token there, or if the
-- parse was below it already.
thenRun : (0 r, c1, c2 : Bool) -> (0 fits : Nat.LTE given n) -> (0 under : Leaves r given bound) ->
          (a -> Grammar state tok bound (c1 || r) c2 b) -> (1 res : Result state tok n c1 given a) ->
          Result state tok n (c1 || c2) given b
thenRun r c1 c2 fits under next (Parsed l fewer inp x)
    = sequenced c1 c2 fewer
        (run (next x) l (transitive (noMore c1 fewer) fits) (readSince r c1 under fewer) inp)
thenRun r c1 c2 fits under next (Failed inp severity errs) = Failed inp severity errs

mapResult : (a -> b) -> (1 res : Result state tok n c given a) -> Result state tok n c given b
mapResult f (Parsed l fewer inp x) = Parsed l fewer inp (f x)
mapResult f (Failed inp severity errs) = Failed inp severity errs

||| Sequence two grammars, the second chosen by the first's value. The
||| sequence consumes if either does, and the second runs below the bound
||| if the first consumes: there it may call a grammar through a box.
export %inline
(>>=) : {0 r, c1, c2 : Bool} ->
        Grammar state tok bound r c1 a -> (a -> Grammar state tok bound (c1 || r) c2 b) ->
        Grammar state tok bound r (c1 || c2) b
p >>= next = MkGrammar (\left, fits, under, inp => thenRun r c1 c2 fits under next (run p left fits under inp))

||| Sequence two grammars. The second is made only once the first has
||| succeeded.
export %inline
(>>) : {0 r, c1, c2 : Bool} ->
       Grammar state tok bound r c1 () -> Lazy (Grammar state tok bound (c1 || r) c2 a) ->
       Grammar state tok bound r (c1 || c2) a
p >> q = MkGrammar (\left, fits, under, inp => thenRun r c1 c2 fits under (\_ => q) (run p left fits under inp))

||| A grammar's value mapped. Neither where it runs nor whether it consumes
||| is part of its value, so the mapping is one for every grammar.
export
{0 bound : Nat} -> {0 r, c : Bool} ->
Functor (Grammar state tok bound r c) where
  map f p = MkGrammar (\left, fits, under, inp => mapResult f (run p left fits under inp))

||| The function the first grammar gives, applied to the value the second
||| gives. The sequence consumes if either does.
export %inline
(<*>) : {0 r, c1, c2 : Bool} ->
        Grammar state tok bound r c1 (a -> b) -> Grammar state tok bound (c1 || r) c2 a ->
        Grammar state tok bound r (c1 || c2) b
f <*> x = MkGrammar (\left, fits, under, inp => thenRun r c1 c2 fits under (\g => map g x) (run f left fits under inp))

||| Two grammars in sequence, the first one's value kept.
export %inline
(<*) : {0 r, c1, c2 : Bool} ->
       Grammar state tok bound r c1 a -> Grammar state tok bound (c1 || r) c2 b ->
       Grammar state tok bound r (c1 || c2) a
x <* y = map const x <*> y

||| Two grammars in sequence, the second one's value kept.
export %inline
(*>) : {0 r, c1, c2 : Bool} ->
       Grammar state tok bound r c1 a -> Grammar state tok bound (c1 || r) c2 b ->
       Grammar state tok bound r (c1 || c2) b
x *> y = map (const id) x <*> y

||| Two alternative grammars: the first, or else the second, from the same
||| place. The choice consumes if both do.
export %inline
(<|>) : Backtrack mark state => {0 r, c1, c2 : Bool} ->
        Grammar state tok bound r c1 ty -> Lazy (Grammar state tok bound r c2 ty) ->
        Grammar state tok bound r (c1 && c2) ty
x <|> y = MkGrammar (\left, fits, under => alternative c1 c2 (run x left fits under) (run y left fits under))

------------------------------------------------------------------------------
-- Where a grammar runs against its bound
------------------------------------------------------------------------------

||| The grammar, run where more is known to have been read since its bound,
||| by `d`: it needs no more than it did. What follows a grammar that may
||| consume runs so.
export
onward : {0 d, r : Bool} -> Grammar state tok bound r c ty -> Grammar state tok bound (d || r) c ty
onward g = MkGrammar (\left, fits, under => run g left fits (earlier d r under))

||| The grammar, run only once a token has been read since its bound.
export
later : Grammar state tok bound r c ty -> Grammar state tok bound True c ty
later = onward {d = True}

------------------------------------------------------------------------------
-- Single steps
------------------------------------------------------------------------------

||| Success, reading nothing.
export
pure : (val : ty) -> Grammar state tok bound r False ty
pure val = MkGrammar (\left, fits, under, inp => Parsed left reflexive inp val)

gave : (left : Nat) -> Columns tok n -> (1 step : Stepped state a) ->
       (1 warned : Trail (Maybe Bounds, String)) -> Commitment -> Result state tok n False left a
gave left cols (MkStepped st x) warned com = Parsed left reflexive (MkInput cols st warned com) x

stepped : (left : Nat) -> ((1 st : state) -> Stepped state a) ->
          (1 inp : Input state tok n) -> Result state tok n False left a
stepped left step (MkInput cols st warned com) = gave left cols (step st) warned com

||| A step of the parse's state, giving a value. A branch that fails is
||| backtracked over its steps, as over its warnings.
export
updateState : ((1 st : state) -> Stepped state a) -> Grammar state tok bound r False a
updateState step = MkGrammar (\left, fits, under, inp => stepped left step inp)

-- One token read by `f`, if one is left and `f` takes it.
readToken : String -> (tok -> Maybe a) -> (left : Nat) -> (0 fits : Nat.LTE left n) ->
            (1 inp : Input state tok n) -> Result state tok n True left a
readToken err f Z fits inp = Failed inp Recoverable (Error "End of input" Nothing ::: [])
readToken err f (S l) fits (MkInput cols st warned com)
    = case f (tokenAt cols l fits) of
           Just x => Parsed l reflexive (MkInput cols st warned com) x
           Nothing => Failed (MkInput cols st warned com) Recoverable
                             (Error err (Just (boundsAt cols l fits)) ::: [])

||| The value `f` makes of the next token, if it makes one; otherwise a
||| failure, with `err`.
export
terminal : String -> (tok -> Maybe a) -> Grammar state tok bound r True a
terminal err f = MkGrammar (\left, fits, under, inp => readToken err f left fits inp)

-- One token read by `f`, with where it was read.
readTokenAt : String -> (tok -> Maybe a) -> (left : Nat) -> (0 fits : Nat.LTE left n) ->
              (1 inp : Input state tok n) -> Result state tok n True left (a, Bounds)
readTokenAt err f Z fits inp = Failed inp Recoverable (Error "End of input" Nothing ::: [])
readTokenAt err f (S l) fits (MkInput cols st warned com)
    = case f (tokenAt cols l fits) of
           Just x => Parsed l reflexive (MkInput cols st warned com) (x, boundsAt cols l fits)
           Nothing => Failed (MkInput cols st warned com) Recoverable
                             (Error err (Just (boundsAt cols l fits)) ::: [])

||| As `terminal`, with where the token was read, which a token always has.
export
terminalAt : String -> (tok -> Maybe a) -> Grammar state tok bound r True (a, Bounds)
terminalAt err f = MkGrammar (\left, fits, under, inp => readTokenAt err f left fits inp)

-- The next token, looked at and not read, where `f` holds of it.
lookAt : String -> (tok -> Bool) -> (left : Nat) -> (0 fits : Nat.LTE left n) ->
         (1 inp : Input state tok n) -> Result state tok n False left tok
lookAt err f Z fits inp = Failed inp Recoverable (Error "End of input" Nothing ::: [])
lookAt err f (S l) fits (MkInput cols st warned com)
    = let t = tokenAt cols l fits in
          if f t
             then Parsed (S l) reflexive (MkInput cols st warned com) t
             else Failed (MkInput cols st warned com) Recoverable
                         (Error err (Just (boundsAt cols l fits)) ::: [])

||| The next token, where `f` holds of it, read no further.
export
nextIs : String -> (tok -> Bool) -> Grammar state tok bound r False tok
nextIs err f = MkGrammar (\left, fits, under, inp => lookAt err f left fits inp)

||| The next token, read no further.
export
peek : Grammar state tok bound r False tok
peek = nextIs "Unrecognised token" (const True)

-- Success where no token is left.
atEnd : (left : Nat) -> (0 fits : Nat.LTE left n) ->
        (1 inp : Input state tok n) -> Result state tok n False left ()
atEnd Z fits inp = Parsed Z reflexive inp ()
atEnd (S l) fits (MkInput cols st warned com)
    = Failed (MkInput cols st warned com) Recoverable
             (Error "Expected end of input" (Just (boundsAt cols l fits)) ::: [])

||| Success where no token is left.
export
eof : Grammar state tok bound r False ()
eof = MkGrammar (\left, fits, under, inp => atEnd left fits inp)

-- Where the next token was read, looked at and not read.
nextPlace : (left : Nat) -> (0 fits : Nat.LTE left n) ->
            (1 inp : Input state tok n) -> Result state tok n False left Bounds
nextPlace Z fits inp = Failed inp Recoverable (Error "End of input" Nothing ::: [])
nextPlace (S l) fits (MkInput cols st warned com)
    = Parsed (S l) reflexive (MkInput cols st warned com) (boundsAt cols l fits)

||| Where the next token was read.
export
position : Grammar state tok bound r False Bounds
position = MkGrammar (\left, fits, under, inp => nextPlace left fits inp)

-- A failure is where it says, or else at the next token, if one is left.
placed : Maybe Bounds -> Columns tok n -> (left : Nat) -> (0 fits : Nat.LTE left n) -> Maybe Bounds
placed (Just b) cols left fits = Just b
placed Nothing cols left fits = nextBounds cols left fits

failedWith : Severity -> Maybe Bounds -> String -> (left : Nat) -> (0 fits : Nat.LTE left n) ->
             (1 inp : Input state tok n) -> Result state tok n c left ty
failedWith severity location msg left fits (MkInput cols st warned com)
    = Failed (MkInput cols st warned com) severity
             (Error msg (placed location cols left fits) ::: [])

failWith : Severity -> Maybe Bounds -> String -> Grammar state tok bound r c ty
failWith severity location msg = MkGrammar (\left, fits, under, inp => failedWith severity location msg left fits inp)

||| A failure, which an alternative recovers from by trying its next branch.
export %inline
fail : {0 c : Bool} -> String -> Grammar state tok bound r c ty
fail = failWith Recoverable Nothing

||| A failure at the bounds given, which an alternative recovers from.
export %inline
failLoc : {0 c : Bool} -> Maybe Bounds -> String -> Grammar state tok bound r c ty
failLoc = failWith Recoverable

||| A failure no alternative recovers from: the parse fails, unless `try`
||| catches it.
export %inline
fatalError : {0 c : Bool} -> String -> Grammar state tok bound r c ty
fatalError = failWith Fatal Nothing

||| A failure at the bounds given that no alternative recovers from.
export %inline
fatalLoc : {0 c : Bool} -> Maybe Bounds -> String -> Grammar state tok bound r c ty
fatalLoc = failWith Fatal

committing : (1 inp : Input state tok n) -> Input state tok n
committing (MkInput cols st warned _) = MkInput cols st warned Committed

||| A commit point: once the branch an alternative is trying has passed it,
||| the alternative tries no other branch.
export
commit : Grammar state tok bound r False ()
commit = MkGrammar (\left, fits, under, inp => Parsed left reflexive (committing inp) ())

recovering : (1 res : Result state tok n c given ty) -> Result state tok n c given ty
recovering (Failed inp _ errs) = Failed inp Recoverable errs
recovering res = res

||| The grammar, its fatal failure made one an alternative recovers from.
||| Whether it passed a commit point stays as it was.
export
try : Grammar state tok bound r c ty -> Grammar state tok bound r c ty
try g = MkGrammar (\left, fits, under, inp => recovering (run g left fits under inp))

fatally : (1 res : Result state tok n c given ty) -> Result state tok n c given ty
fatally (Failed inp _ errs) = Failed inp Fatal errs
fatally res = res

||| The grammar, any failure of it made fatal.
export
mustWork : Grammar state tok bound r c ty -> Grammar state tok bound r c ty
mustWork g = MkGrammar (\left, fits, under, inp => fatally (run g left fits under inp))

------------------------------------------------------------------------------
-- What a grammar read
------------------------------------------------------------------------------

||| Whether a grammar read a token: some, leaving fewer than it was given,
||| or none.
public export
data Reading : (left, given : Nat) -> Type where
  ReadSome : (0 fewer : Nat.LT left given) -> Reading left given
  ReadNone : Reading left given

||| Whether a grammar that may read a token did, from what it left: one
||| that consumes always did, which its type says, so asking costs
||| nothing; any other is looked at.
public export
interface Consumes (0 c : Bool) where
  reading : (left, given : Nat) -> (0 leaves : Leaves c left given) -> Reading left given

export
Consumes True where
  reading left given fewer = ReadSome fewer

export
Consumes False where
  reading left given within
      = case choose (left < given) of
             Left less => ReadSome (ltOpReflectsLT left given less)
             Right _ => ReadNone

-- The bounds of the tokens read, from the first to the last: tokens are
-- read in order, so these are the bounds of all of them.
spanOf : Columns tok n -> (given, left : Nat) ->
         (0 fits : Nat.LTE given n) -> (0 fewer : Nat.LT left given) -> Bounds
spanOf cols (S g) left fits fewer = union (boundsAt cols g fits) (boundsAt cols left (transitive fewer fits))
spanOf _ Z _ _ (LTESucc _) impossible

-- The bounds of what was read, if anything was.
spanRead : Columns tok n -> (given, left : Nat) -> (0 fits : Nat.LTE given n) ->
           Reading left given -> Maybe Bounds
spanRead cols given left fits (ReadSome fewer) = Just (spanOf cols given left fits fewer)
spanRead cols given left fits ReadNone = Nothing

-- A value with the bounds of what was read to make it, none if nothing was.
boundsOf : Columns tok n -> (given, left : Nat) -> (0 fits : Nat.LTE given n) ->
           Reading left given -> ty -> WithBounds ty
boundsOf cols given left fits (ReadSome fewer) v = Relevant v (spanOf cols given left fits fewer)
boundsOf cols given left fits ReadNone v = Irrelevant v

located : Consumes c => (given : Nat) -> (0 fits : Nat.LTE given n) ->
          (1 res : Result state tok n c given ty) -> Result state tok n c given (WithBounds ty)
located given fits (Parsed l fewer (MkInput cols st warned com) v)
    = Parsed l fewer (MkInput cols st warned com) (boundsOf cols given l fits (reading l given fewer) v)
located given fits (Failed inp severity errs) = Failed inp severity errs

||| The grammar's value, with the bounds of the tokens it read: from the
||| first to the last, and none if it read none.
export
bounds : Consumes c => Grammar state tok bound r c ty -> Grammar state tok bound r c (WithBounds ty)
bounds p = MkGrammar (\left, fits, under, inp => located left fits (run p left fits under inp))

warnedAfter : Consumes c => String -> (given : Nat) -> (0 fits : Nat.LTE given n) ->
              (1 res : Result state tok n c given ty) -> Result state tok n c given ty
warnedAfter msg given fits (Parsed l fewer (MkInput cols st warned com) v)
    = let at = spanRead cols given l fits (reading l given fewer) in
          Parsed l fewer (MkInput cols st (write (at, msg) warned) com) v
warnedAfter msg given fits (Failed inp severity errs) = Failed inp severity errs

||| The grammar, warning where it succeeds, at the bounds of what it read.
export
withWarning : Consumes c => String -> Grammar state tok bound r c ty -> Grammar state tok bound r c ty
withWarning msg p = MkGrammar (\left, fits, under, inp => warnedAfter msg left fits (run p left fits under inp))

------------------------------------------------------------------------------
-- Repetition
------------------------------------------------------------------------------

-- What a round read leaves fewer tokens: its entry first, then the rounds
-- after it.
prepend : a -> (0 fewer : Nat.LT l given) -> (1 res : Result state tok n False l (List a)) ->
          Result state tok n True given (List a)
prepend x fewer (Parsed l' within inp xs) = Parsed l' (transitive (LTESucc within) fewer) inp (x :: xs)
prepend x fewer (Failed inp severity errs) = Failed inp severity errs

-- A round of a repetition: the round's grammar run, and, where it read
-- what it reads, the rounds after it from where it stopped.
round : (1 res : Result state tok n True given r) -> (entry : r -> a) ->
        (rest : r -> (l : Nat) -> (0 fewer : Nat.LT l given) -> RunFrom state tok n False l (List a)) ->
        Result state tok n True given (List a)
round (Parsed l fewer inp x) entry rest = prepend (entry x) fewer (rest x l fewer inp)
round (Failed inp severity errs) entry rest = Failed inp severity errs

-- No more rounds.
noRounds : (given : Nat) -> RunFrom state tok n False given (List a)
noRounds given inp = Parsed given reflexive inp []

-- `p` round after round, each round an alternative between `p` followed by
-- the rounds after it and no more rounds: so a round that fails before a
-- commit point ends the repetition, and one past a commit point fails it
-- as such an alternative fails. Each round reads a token, so the rounds
-- after it start from fewer tokens: the recursion is on them. Each round
-- stands against the bound as the first did, at least.
manyAt : Backtrack mark state => {0 r : Bool} ->
         Grammar state tok bound r True a -> (given : Nat) -> (0 fits : Nat.LTE given n) ->
         (0 under : Leaves r given bound) ->
         (0 acc : Accessible Nat.LT given) -> RunFrom state tok n False given (List a)
manyAt p given fits under (Access rec)
    = alternative True False
        (\inp => round (run p given fits under inp) id
                       (\_, l, fewer, inp' => manyAt p l (transitive (noMore True fewer) fits)
                                                (further r (noMore True fewer) under) (rec l fewer) inp'))
        (noRounds given)

||| `p` as many times as it succeeds, none at least. A round that fails
||| past a commit point fails the repetition.
export
many : Backtrack mark state => Grammar state tok bound r True a -> Grammar state tok bound r False (List a)
many p = MkGrammar (\left, fits, under => manyAt p left fits under (wellFounded left))

||| `p` once, and then as many times as it succeeds.
export
some : Backtrack mark state => Grammar state tok bound r True a -> Grammar state tok bound r True (List1 a)
some p = p >>= \x => map (x :::) (later (many p))

-- The entries of a block from `given` tokens: none where `stop` succeeds;
-- otherwise the entry the seed chooses, followed by the entries after it
-- from the seed it gives, or none where it fails before a commit point.
entriesAt : Backtrack mark state => {0 r : Bool} ->
            (stop : Grammar state tok bound r False ()) ->
            (entry : seed -> Grammar state tok bound r True (a, seed)) ->
            seed -> (given : Nat) -> (0 fits : Nat.LTE given n) -> (0 under : Leaves r given bound) ->
            (0 acc : Accessible Nat.LT given) -> RunFrom state tok n False given (List a)
entriesAt stop entry s given fits under (Access rec)
    = alternative False False
        (\inp => mapResult (const []) (run stop given fits under inp))
        (alternative True False
           (\inp => round (run (entry s) given fits under inp) fst
                          (\x, l, fewer, inp' => entriesAt stop entry (snd x) l
                                                   (transitive (noMore True fewer) fits)
                                                   (further r (noMore True fewer) under) (rec l fewer) inp'))
           (noRounds given))

||| A block's entries: each read by the grammar the seed chooses, each
||| giving the seed of the next, until `stop` succeeds or an entry fails
||| before a commit point. An entry that fails past one fails the block.
export
entries : Backtrack mark state =>
          (stop : Grammar state tok bound r False ()) ->
          (entry : seed -> Grammar state tok bound r True (a, seed)) ->
          seed -> Grammar state tok bound r False (List a)
entries stop entry s = MkGrammar (\left, fits, under => entriesAt stop entry s left fits under (wellFounded left))

------------------------------------------------------------------------------
-- Recursion between grammars
------------------------------------------------------------------------------

||| What a grammar at bound `n` reaches another grammar through: the `p` at
||| every bound below `n`. A grammar has what a box holds only once it has
||| read a token, and only at the bound it then stands at, so a grammar that
||| names itself through a box names a grammar at a smaller bound. What a
||| box holds is suspended, as its bound and evidence are erased: it is made
||| where a grammar opens the box, never where the box is.
public export
Box : (Nat -> Type) -> Nat -> Type
Box p n = {0 m : Nat} -> (0 below : Nat.LT m n) -> Lazy (p m)

||| A family of grammars at every bound, made at each bound of the box of
||| itself: the one fixpoint that ties grammars to their names. It recurses
||| on the bound, which is erased, so it costs nothing beyond making the
||| family at the bound a box is opened at.
export
fixpoint : {0 p : Nat -> Type} -> {0 n : Nat} -> (step : {0 m : Nat} -> Box p m -> p m) -> p n
fixpoint {p} {n} step = tied (wellFounded n)
  where
    tied : {0 k : Nat} -> (0 acc : Accessible Nat.LT k) -> p k
    tied (Access rec) = step (\below => tied (rec _ below))

||| The grammar `pick` takes of what the box holds where the parse stands.
||| It runs only once a token has been read since the box's bound, so the
||| parse stands below it, and what it calls is bounded by where it stands.
export
call : Box p bound -> (pick : {0 m : Nat} -> p m -> Grammar state tok m False c ty) ->
       Grammar state tok bound True c ty
call box pick = MkGrammar (\left, fits, under => run (pick {m = left} (box under)) left fits reflexive)

------------------------------------------------------------------------------
-- Running
------------------------------------------------------------------------------

-- The result of a whole parse: matched once its input is no longer held,
-- so its state is dropped where it failed.
finished : Result state tok n c given ty -> Either (List1 ParsingError) (state, ParsingWarnings, ty)
finished (Parsed _ _ (MkInput _ st warned _) v) = Right (st, contents warned, v)
finished (Failed _ _ errs) = Left errs

||| Parse the tokens by the grammar, from the first, its state `initial` to
||| begin with: the state it ends with, its warnings in the order given,
||| and its value; or its errors. The grammar is had at every bound, and runs
||| at the number of tokens. A grammar that must read every token ends with
||| `eof`.
export
parseWith : (initial : state) -> (act : {0 n : Nat} -> Grammar state tok n False c ty) -> Tokens tok ->
            Either (List1 ParsingError) (state, ParsingWarnings, ty)
parseWith initial act (MkTokens extent cols)
    = finished (run (act {n = extent}) extent reflexive reflexive (MkInput cols initial blank Open))

||| Parse the tokens by a grammar that keeps no state.
export
parse : (act : {0 n : Nat} -> Grammar () tok n False c ty) -> Tokens tok ->
        Either (List1 ParsingError) (ParsingWarnings, ty)
parse act toks = map dropState (parseWith () act toks)
  where
    dropState : ((), ParsingWarnings, ty) -> (ParsingWarnings, ty)
    dropState (_, ws, v) = (ws, v)
