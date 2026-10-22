-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Libraries.Text.Parser.Core

import Control.WellFounded
import Data.Bool
import Data.List
import Data.List1
import Data.Nat

import Array

import public Libraries.Control.Delayed
import public Libraries.Text.Bounded

%default total

%hide Prelude.(>>)

-- TODO: Add some primitives for helping with error messages.
-- e.g. perhaps set a string to state what we're currently trying to
-- parse, or to say what the next expected token is in words

||| Description of a language's grammar. The `tok` parameter is the type
||| of tokens, and the `consumes` flag is True if the language is guaranteed
||| to be non-empty - that is, successfully parsing the language is guaranteed
||| to consume some input.
|||
||| Whether a part consumes is known from its type, so no constructor keeps
||| it at runtime: the flags of a sequence's and an alternative's parts are
||| erased.
export
data Grammar : (state : Type) -> (tok : Type) -> (consumes : Bool) -> Type -> Type where
     Empty : (val : ty) -> Grammar state tok False ty
     Terminal : String -> (tok -> Maybe a) -> Grammar state tok True a
     NextIs : String -> (tok -> Bool) -> Grammar state tok False tok
     EOF : Grammar state tok False ()

     Fail : (location : Maybe Bounds) -> (fatal : Bool) -> String -> Grammar state tok c ty
     Warning : (location : Maybe Bounds) -> String -> Grammar state tok False ()

     Try : Grammar state tok c ty -> Grammar state tok c ty

     Commit : Grammar state tok False ()
     MustWork : Grammar state tok c a -> Grammar state tok c a

     SeqEat : {0 c2 : Bool} ->
              Grammar state tok True a -> Inf (a -> Grammar state tok c2 b) ->
              Grammar state tok True b
     SeqEmpty : {0 c1, c2 : Bool} ->
                Grammar state tok c1 a -> (a -> Grammar state tok c2 b) ->
                Grammar state tok (c1 || c2) b

     ThenEat : {0 c2 : Bool} ->
               Grammar state tok True () -> Inf (Grammar state tok c2 a) ->
               Grammar state tok True a
     ThenEmpty : {0 c1, c2 : Bool} ->
                 Grammar state tok c1 () -> Grammar state tok c2 a ->
                 Grammar state tok (c1 || c2) a

     Alt : {0 c1, c2 : Bool} ->
           Grammar state tok c1 ty -> Lazy (Grammar state tok c2 ty) ->
           Grammar state tok (c1 && c2) ty
     Bounds : Grammar state tok c ty -> Grammar state tok c (WithBounds ty)
     Position : Grammar state tok False Bounds

     UpdateState : (state -> (state, a)) -> Grammar state tok False a

||| Sequence two grammars. If either consumes some input, the sequence is
||| guaranteed to consume some input. If the first one consumes input, the
||| second is allowed to be recursive (because it means some input has been
||| consumed and therefore the input is smaller)
export %inline
(>>=) : {c1, c2 : Bool} ->
        Grammar state tok c1 a ->
        inf c1 (a -> Grammar state tok c2 b) ->
        Grammar state tok (c1 || c2) b
(>>=) {c1 = False} = SeqEmpty
(>>=) {c1 = True}  = SeqEat

||| Sequence two grammars. If either consumes some input, the sequence is
||| guaranteed to consume some input. If the first one consumes input, the
||| second is allowed to be recursive (because it means some input has been
||| consumed and therefore the input is smaller)
public export %inline %tcinline
(>>) : {c1, c2 : Bool} ->
        Grammar state tok c1 () ->
        inf c1 (Grammar state tok c2 a) ->
        Grammar state tok (c1 || c2) a
(>>) {c1 = False} = ThenEmpty
(>>) {c1 = True} = ThenEat

||| Sequence two grammars. If either consumes some input, the sequence is
||| guaranteed to consume input. This is an explicitly non-infinite version
||| of `>>=`.
export %inline
seq : {c1,c2 : Bool} ->
      Grammar state tok c1 a ->
      (a -> Grammar state tok c2 b) ->
      Grammar state tok (c1 || c2) b
seq = SeqEmpty

||| Sequence a grammar followed by the grammar it returns.
export %inline
join : {c1,c2 : Bool} ->
       Grammar state tok c1 (Grammar state tok c2 a) ->
       Grammar state tok (c1 || c2) a
join {c1 = False} p = SeqEmpty p id
join {c1 = True} p = SeqEat p id

||| Allows the result of a grammar to be mapped to a different value. Whether
||| the grammar consumes is no part of mapping its result, so the
||| implementation is one for every grammar, not one chosen by it at runtime.
export
{0 c : _} ->
Functor (Grammar state tok c) where
  map f (Empty val)  = Empty (f val)
  map f (Fail bd fatal msg) = Fail bd fatal msg
  map f (Try g) = Try (map f g)
  map f (MustWork g) = MustWork (map f g)
  map f (Terminal msg g) = Terminal msg (map f . g)
  map f (Alt x y)    = Alt (map f x) (map f y)
  map f (SeqEat act next)
      = SeqEat act (\val => map f (next val))
  map f (SeqEmpty act next)
      = SeqEmpty act (\ val => map f (next val))
  map f (ThenEat act next)
      = ThenEat act (map f next)
  map f (ThenEmpty act next)
      = ThenEmpty act (map f next)
  map {c} f (Bounds act)
    = rewrite sym $ orFalseNeutral c in
      SeqEmpty (Bounds act) (Empty . f) -- Bounds (map f act)
  map f (UpdateState step)
      = UpdateState (\st => let (st', x) = step st in (st', f x))
  -- The remaining constructors have a fixed type, so a sequence must be
  -- used.
  map f p@(NextIs _ _) = SeqEmpty p (Empty . f)
  map f EOF = SeqEmpty EOF (Empty . f)
  map f p@(Warning _ _) = SeqEmpty p (Empty . f)
  map f Commit = SeqEmpty Commit (Empty . f)
  map f Position = SeqEmpty Position (Empty . f)

||| Give two alternative grammars. If both consume, the combination is
||| guaranteed to consume.
export %inline
(<|>) : {c1,c2 : Bool} ->
        Grammar state tok c1 ty ->
        Lazy (Grammar state tok c2 ty) ->
        Grammar state tok (c1 && c2) ty
(<|>) = Alt

export infixr 2 <||>
||| Take the tagged disjunction of two grammars. If both consume, the
||| combination is guaranteed to consume.
export
(<||>) : {c1,c2 : Bool} ->
        Grammar state tok c1 a ->
        Lazy (Grammar state tok c2 b) ->
        Grammar state tok (c1 && c2) (Either a b)
(<||>) p q = (Left <$> p) <|> (Right <$> q)

||| Sequence a grammar with value type `a -> b` and a grammar
||| with value type `a`. If both succeed, apply the function
||| from the first grammar to the value from the second grammar.
||| Guaranteed to consume if either grammar consumes.
export %inline
(<*>) : {c1, c2 : Bool} ->
        Grammar state tok c1 (a -> b) ->
        Grammar state tok c2 a ->
        Grammar state tok (c1 || c2) b
(<*>) x y = SeqEmpty x (\f => map f y)

||| Sequence two grammars. If both succeed, use the value of the first one.
||| Guaranteed to consume if either grammar consumes.
export %inline
(<*) : {c1,c2 : Bool} ->
       Grammar state tok c1 a ->
       Grammar state tok c2 b ->
       Grammar state tok (c1 || c2) a
(<*) x y = map const x <*> y

||| Sequence two grammars. If both succeed, use the value of the second one.
||| Guaranteed to consume if either grammar consumes.
export %inline
(*>) : {c1,c2 : Bool} ->
       Grammar state tok c1 a ->
       Grammar state tok c2 b ->
       Grammar state tok (c1 || c2) b
(*>) x y = map (const id) x <*> y

||| A step of the grammar's state, giving a value. A branch that fails
||| drops its steps, as it drops its warnings.
export %inline
updateState : (state -> (state, a)) -> Grammar state tok False a
updateState = UpdateState

||| Always succeed with the given value.
export %inline
pure : (val : ty) -> Grammar state tok False ty
pure = Empty

||| Check whether the next token satisfies a predicate
export %inline
nextIs : String -> (tok -> Bool) -> Grammar state tok False tok
nextIs = NextIs

||| Look at the next token in the input
export %inline
peek : Grammar state tok False tok
peek = nextIs "Unrecognised token" (const True)

||| As `terminal`, with the bounds of the token read, which a token always
||| has.
export
terminalAt : String -> (tok -> Maybe a) -> Grammar state tok True (a, Bounds)
terminalAt err f
    = SeqEmpty Position (\loc => SeqEat (Terminal err f) (\a => Empty (a, loc)))

||| Succeeds if running the predicate on the next token returns Just x,
||| returning x. Otherwise fails.
export %inline
terminal : String -> (tok -> Maybe a) -> Grammar state tok True a
terminal = Terminal

||| Always fail with a message
export %inline
fail : String -> Grammar state tok c ty
fail = Fail Nothing False

||| Always fail with a message and a location
export %inline
failLoc : Maybe Bounds -> String -> Grammar state tok c ty
failLoc b = Fail b False

||| Fail with no possibility for recovery (i.e.
||| no alternative parsing can succeed).
export %inline
fatalError : String -> Grammar state tok c ty
fatalError = Fail Nothing True

||| Fail with no possibility for recovery (i.e.
||| no alternative parsing can succeed).
export %inline
fatalLoc : Maybe Bounds -> String -> Grammar state tok c ty
fatalLoc b = Fail b True

||| Catch a fatal error
export %inline
try : Grammar state tok c ty -> Grammar state tok c ty
try = Try

||| Succeed if the input is empty
export %inline
eof : Grammar state tok False ()
eof = EOF

||| Commit to an alternative; if the current branch of an alternative
||| fails to parse, no more branches will be tried
export %inline
commit : Grammar state tok False ()
commit = Commit

||| If the parser fails, treat it as a fatal error
export %inline
mustWork : {c : Bool} -> Grammar state tok c ty -> Grammar state tok c ty
mustWork = MustWork

||| If the parser fails, treat it as a fatal error and explain why
export
mustWorkBecause :
  {c : Bool} -> Maybe Bounds -> String ->
  Grammar state tok c ty -> Grammar state tok c ty
mustWorkBecause {c} loc msg p
  = rewrite sym (andSameNeutral c) in
    p <|> fatalLoc loc msg

export %inline
bounds : Grammar state tok c ty -> Grammar state tok c (WithBounds ty)
bounds = Bounds

export
mustFailBecause :
  String ->
  Grammar state tok True ty -> Grammar state tok False Unit
mustFailBecause msg p
  = (bounds p >>= \res => fatalLoc {c=False} res.bounds msg) <|> pure ()

export %inline
position : Grammar state tok False Bounds
position = Position

||| Warn the user
export %inline
withWarning : {c : _} -> String -> Grammar state tok c ty -> Grammar state tok c ty
withWarning warn p
    = rewrite sym $ orFalseNeutral c in
      SeqEmpty (bounds p) $ \ res =>
      do Warning res.bounds warn
         pure res.val

public export
data ParsingError tok = Error String (Maybe Bounds)

public export
ParsingWarnings : Type
ParsingWarnings = List (Maybe Bounds, String)

||| The tokens a grammar reads, as columns: for each token, the token and
||| where it was read. A token's position is the number of tokens after it,
||| so the last is at 0: where a parse stands is how many tokens it has
||| left, which is what it recurses on, and the next token is at that
||| number less one, read with no arithmetic.
export
record Tokens tok where
  constructor MkTokens
  extent : Nat
  vals : Vector extent tok
  spans : Vector extent Bounds

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
                   (replace {p = \k => Vector k tok} (lengthMap ts) (Array.fromList (map value ts)))
                   (replace {p = \k => Vector k Bounds} (lengthMap ts) (Array.fromList (map place ts)))

-- The token with `l` tokens after it, and where it was read.
tokenAt : (toks : Tokens tok) -> (l : Nat) -> (0 fits : LT l (extent toks)) -> tok
tokenAt toks l fits = vals toks !! [<natToFinLT l {prf = fits}]

boundsAt : (toks : Tokens tok) -> (l : Nat) -> (0 fits : LT l (extent toks)) -> Bounds
boundsAt toks l fits = spans toks !! [<natToFinLT l {prf = fits}]

-- Where the next token was read, unless no token is left.
nextBounds : (toks : Tokens tok) -> (left : Nat) -> (0 fits : LTE left (extent toks)) -> Maybe Bounds
nextBounds toks Z _ = Nothing
nextBounds toks (S l) fits = Just (boundsAt toks l fits)

-- How many tokens a grammar leaves, `left`, against how many it was
-- given: fewer if it consumes, never more. A parse ends because each
-- grammar's result carries this, erased.
Leaves : (consumes : Bool) -> (left, given : Nat) -> Type
Leaves True left given = LT left given
Leaves False left given = LTE left given

0 noMore : (c : Bool) -> Leaves c left given -> LTE left given
noMore True fewer = lteSuccLeft fewer
noMore False fewer = fewer

0 within : (c : Bool) -> Leaves c left middle -> LTE middle given -> Leaves c left given
within True fewer le = transitive fewer le
within False fewer le = transitive fewer le

-- Two grammars in sequence leave what the second leaves, fewer than the
-- first was given if either consumes.
0 inSequence : (c1, c2 : Bool) ->
               Leaves c1 middle given -> Leaves c2 left middle ->
               Leaves (c1 || c2) left given
inSequence True c2 first second = transitive (LTESucc (noMore c2 second)) first
inSequence False c2 first second = within c2 second first

-- An alternative leaves what the branch taken leaves, fewer than it was
-- given if both branches consume.
0 firstOf : (c1, c2 : Bool) -> Leaves c1 left given -> Leaves (c1 && c2) left given
firstOf True True fewer = fewer
firstOf True False fewer = noMore True fewer
firstOf False _ fewer = fewer

0 secondOf : (c1, c2 : Bool) -> Leaves c2 left given -> Leaves (c1 && c2) left given
secondOf True _ fewer = fewer
secondOf False c2 fewer = noMore c2 fewer

data ParseResult : (state : Type) -> (tok : Type) -> (consumes : Bool) -> (given : Nat) -> Type -> Type where
     Failure : (committed : Bool) -> (fatal : Bool) ->
               List1 (ParsingError tok) -> ParseResult state tok c given ty
     Res : state ->
           (ws : ParsingWarnings) ->
           (committed : Bool) ->
           (val : WithBounds ty) ->
           (left : Nat) -> (0 fewer : Leaves c left given) ->
           ParseResult state tok c given ty

-- The result of what followed a first grammar, at the bounds of both, as
-- the result of the two from where the first began.
mergeWith : (0 c1, c2 : Bool) -> (0 first : Leaves c1 middle given) -> WithBounds ty ->
            ParseResult state tok c2 middle sy -> ParseResult state tok (c1 || c2) given sy
mergeWith c1 c2 first x (Res s ws committed val left second)
    = Res s ws committed (mergeBounds x val) left (inSequence c1 c2 first second)
mergeWith c1 c2 first x (Failure com fatal errs) = Failure com fatal errs

-- A parse recurses on its grammar, but a grammar after one that consumed
-- (`SeqEat`, `ThenEat`) is made by a function the parse forces, no part of
-- the grammar it was given: that recursion is on the tokens left, which
-- are accessible (`acc`), bounded by `bound` until a grammar consumes.
doParse : (toks : Tokens tok) ->
          state -> (ws : ParsingWarnings) ->
          (commit : Bool) ->
          (act : Grammar state tok c ty) ->
          (left : Nat) -> (0 fits : LTE left (extent toks)) ->
          (0 acc : Accessible LT bound) -> (0 below : LTE left bound) ->
          ParseResult state tok c left ty
doParse toks s ws com (Empty val) left fits acc below = Res s ws com (Irrelevant val) left reflexive
doParse toks s ws com (Warning mb msg) left fits acc below = Res s ((mb, msg) :: ws) com (Irrelevant ()) left reflexive
doParse toks s ws com (Fail location fatal str) left fits acc below
    = Failure com fatal (Error str (location <|> nextBounds toks left fits) ::: Nil)
doParse toks s ws com (Try g) left fits acc below = case doParse toks s ws com g left fits acc below of
  -- recover from fatal match but still propagate the 'commit'
  Failure com _ errs => Failure com False errs
  res => res
doParse toks s ws com Commit left fits acc below = Res s ws True (Irrelevant ()) left reflexive
doParse toks s ws com (MustWork g) left fits acc below =
  case doParse toks s ws com g left fits acc below of
       Failure com' _ errs => Failure com' True errs
       res => res
doParse toks s ws com (Terminal err f) Z fits acc below = Failure com False (Error "End of input" Nothing ::: Nil)
doParse toks s ws com (Terminal err f) (S l) fits acc below =
  case f (tokenAt toks l fits) of
       Nothing => Failure com False (Error err (Just (boundsAt toks l fits)) ::: Nil)
       Just a => Res s ws com (Relevant a (boundsAt toks l fits)) l reflexive
doParse toks s ws com EOF Z fits acc below = Res s ws com (Irrelevant ()) Z reflexive
doParse toks s ws com EOF (S l) fits acc below = Failure com False (Error "Expected end of input" (Just (boundsAt toks l fits)) ::: Nil)
doParse toks s ws com (NextIs err f) Z fits acc below = Failure com False (Error "End of input" Nothing ::: Nil)
doParse toks s ws com (NextIs err f) (S l) fits acc below
      -- a token only looked at locates nothing parsed
      = let t = tokenAt toks l fits in
        if f t
           then Res s ws com (Irrelevant t) (S l) reflexive
           else Failure com False (Error err (Just (boundsAt toks l fits)) ::: Nil)
doParse toks s ws com (Alt {c1} {c2} x y) left fits acc below
    = case doParse toks s ws False x left fits acc below of
           Failure com' fatal errs
              => if com' || fatal
                        -- If the alternative had committed, don't try the
                        -- other branch (and reset commit flag)
                   then Failure com fatal errs
                   else case doParse toks s ws False y left fits acc below of
                             (Failure com'' fatal' errs') => if com'' || fatal'
                                                                     -- Only add the errors together if the second branch
                                                                     -- is also non-committed and non-fatal.
                                                             then Failure com'' fatal' errs'
                                                             else Failure com False (errs ++ errs')
                             (Res s ws _ val more fewer) => Res s ws com val more (secondOf c1 c2 fewer)
           -- Successfully parsed the first option, so use the outer commit flag
           Res s ws _ val more fewer => Res s ws com val more (firstOf c1 c2 fewer)
doParse toks s ws com (SeqEmpty {c1} {c2} act next) left fits acc below
    = case doParse toks s ws com act left fits acc below of
           Failure com fatal errs => Failure com fatal errs
           Res s ws com v more fewer =>
             mergeWith c1 c2 fewer v $
               doParse toks s ws com (next v.val) more (transitive (noMore c1 fewer) fits)
                       acc (transitive (noMore c1 fewer) below)
doParse toks s ws com (SeqEat {c2} act next) left fits acc@(Access rec) below
    = case doParse toks s ws com act left fits acc below of
           Failure com fatal errs => Failure com fatal errs
           Res s ws com v more fewer =>
             mergeWith True c2 fewer v $
               doParse toks s ws com (next v.val) more (transitive (lteSuccLeft fewer) fits)
                       (rec more (transitive fewer below)) reflexive
doParse toks s ws com (ThenEmpty {c1} {c2} act next) left fits acc below
    = case doParse toks s ws com act left fits acc below of
           Failure com fatal errs => Failure com fatal errs
           Res s ws com v more fewer =>
             mergeWith c1 c2 fewer v $
               doParse toks s ws com next more (transitive (noMore c1 fewer) fits)
                       acc (transitive (noMore c1 fewer) below)
doParse toks s ws com (ThenEat {c2} act next) left fits acc@(Access rec) below
    = case doParse toks s ws com act left fits acc below of
           Failure com fatal errs => Failure com fatal errs
           Res s ws com v more fewer =>
             mergeWith True c2 fewer v $
               doParse toks s ws com next more (transitive (lteSuccLeft fewer) fits)
                       (rec more (transitive fewer below)) reflexive
doParse toks s ws com (Bounds act) left fits acc below
    = case doParse toks s ws com act left fits acc below of
           Failure com fatal errs => Failure com fatal errs
           Res s ws com v more fewer => Res s ws com (const v <$> v) more fewer
doParse toks s ws com Position Z fits acc below = Failure com False (Error "End of input" Nothing ::: Nil)
doParse toks s ws com Position (S l) fits acc below
    = Res s ws com (Irrelevant (boundsAt toks l fits)) (S l) reflexive
doParse toks s ws com (UpdateState step) left fits acc below
  = let (s', x) = step s in
        Res s' ws com (Irrelevant x) left reflexive

||| Parse tokens according to the given grammar, from the first, its state
||| `initial` to begin with. A grammar that must read them all ends with
||| `eof`.
export
parseWith : {c : Bool} -> (initial : state) -> (act : Grammar state tok c ty) ->
            Tokens tok -> Either (List1 (ParsingError tok)) (state, ParsingWarnings, ty)
parseWith initial act toks
    = case doParse toks initial [] False act (extent toks) reflexive (wellFounded (extent toks)) reflexive of
           Failure _ _ errs => Left errs
           Res s ws _ v _ _ => Right (s, ws, v.val)

||| Parse tokens according to a grammar that keeps no state, from the first.
||| A grammar that must read them all ends with `eof`.
export
parse : {c : Bool} -> (act : Grammar () tok c ty) -> Tokens tok ->
        Either (List1 (ParsingError tok)) (ParsingWarnings, ty)
parse act toks = map (\(_, ws, v) => (ws, v)) (parseWith () act toks)
