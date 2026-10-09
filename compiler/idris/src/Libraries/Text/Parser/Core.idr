module Libraries.Text.Parser.Core

import Data.Bool
import Data.List
import Data.List1

import public Libraries.Control.Delayed
import public Libraries.Text.Bounded

%default total

%hide Prelude.(>>)

-- TODO: Add some primitives for helping with error messages.
-- e.g. perhaps set a string to state what we're currently trying to
-- parse, or to say what the next expected token is in words

public export
data ParsingError tok = Error String (Maybe Bounds)

public export
ParsingWarnings : Type
ParsingWarnings = List (Maybe Bounds, String)

-- What a grammar's actions and warnings have made so far: how to add an
-- action to the state, the state, and the warnings.
record Made state where
  constructor MkMade
  append : state -> state -> state
  st : state
  warnings : ParsingWarnings

-- What a grammar runs on: what has been made, whether the enclosing
-- alternative has committed, and the tokens left. Most steps change only
-- the last two, so they are copied without the rest.
record Input state tok where
  constructor MkInput
  made : Made state
  committed : Bool
  tokens : List (WithBounds tok)

data ParseResult : Type -> Type -> Type -> Type where
     Failure : (committed : Bool) -> (fatal : Bool) ->
               List1 (ParsingError tok) -> ParseResult state tok ty
     Res : (rest : Input state tok) -> (val : WithBounds ty) ->
           ParseResult state tok ty

||| Description of a language's grammar. The `tok` parameter is the type
||| of tokens, and the `consumes` flag is True if the language is guaranteed
||| to be non-empty - that is, successfully parsing the language is guaranteed
||| to consume some input.
|||
||| A grammar is the parser itself, a function from its input to its result.
||| The result type is a parameter, so a sequence's intermediate result is
||| held by the closure of the sequence rather than hidden in a constructor.
|||
||| It is a box around the function, not a newtype: a grammar defined
||| without arguments is then a constant, built once, rather than a function
||| that builds its parts again each time it runs.
export
data Grammar : (state : Type) -> (tok : Type) -> (consumes : Bool) -> (ty : Type) -> Type where
  [noNewtype]
  MkGrammar : (Input state tok -> ParseResult state tok ty) -> Grammar state tok consumes ty

%inline
runGrammar : Grammar state tok c ty -> Input state tok -> ParseResult state tok ty
runGrammar (MkGrammar run) = run

mergeWith : WithBounds ty -> ParseResult state tok sy -> ParseResult state tok sy
mergeWith x (Res inp val) = Res inp (mergeBounds x val)
mergeWith x v = v

firstBounds : List (WithBounds tok) -> Maybe Bounds
firstBounds [] = Nothing
firstBounds (x :: _) = Just x.bounds

withCommitted : Bool -> Input state tok -> Input state tok
withCommitted com inp
    = if inp.committed
         then if com then inp else { committed := False } inp
         else if com then { committed := True } inp else inp

-- Run `act`, then the grammar `next` makes of its value, on the rest of the
-- input.
bindGrammar : Grammar state tok c1 a -> (a -> Grammar state tok c2 b) ->
              Grammar state tok c3 b
bindGrammar act next
    = MkGrammar $ \inp =>
        case runGrammar act inp of
             Failure com fatal errs => Failure com fatal errs
             Res inp v => mergeWith v $ runGrammar (next v.val) inp

-- Run `act`, then `next` on the rest of the input.
thenGrammar : Grammar state tok c1 () -> Grammar state tok c2 a ->
              Grammar state tok c3 a
thenGrammar act next
    = MkGrammar $ \inp =>
        case runGrammar act inp of
             Failure com fatal errs => Failure com fatal errs
             Res inp v => mergeWith v $ runGrammar next inp

-- As `thenGrammar`, with `next` delayed until `act` has succeeded.
thenLater : Grammar state tok c1 () -> Inf (Grammar state tok c2 a) ->
            Grammar state tok c3 a
thenLater act next
    = MkGrammar $ \inp =>
        case runGrammar act inp of
             Failure com fatal errs => Failure com fatal errs
             Res inp v => mergeWith v $ runGrammar next inp

warning : (location : Maybe Bounds) -> String -> Grammar state tok False ()
warning mb msg
    = MkGrammar $ \inp =>
        Res ({ made.warnings $= ((mb, msg) ::) } inp) (irrelevantBounds ())

||| Sequence two grammars. If either consumes some input, the sequence is
||| guaranteed to consume some input. If the first one consumes input, the
||| second is allowed to be recursive (because it means some input has been
||| consumed and therefore the input is smaller)
export %inline
(>>=) : {c1, c2 : Bool} ->
        Grammar state tok c1 a ->
        inf c1 (a -> Grammar state tok c2 b) ->
        Grammar state tok (c1 || c2) b
(>>=) {c1 = False} act next = bindGrammar act next
-- `next` is forced each time `act` has succeeded, never before.
(>>=) {c1 = True}  act next = bindGrammar act (\x => next x)

||| Sequence two grammars. If either consumes some input, the sequence is
||| guaranteed to consume some input. If the first one consumes input, the
||| second is allowed to be recursive (because it means some input has been
||| consumed and therefore the input is smaller)
export %inline
(>>) : {c1, c2 : Bool} ->
        Grammar state tok c1 () ->
        inf c1 (Grammar state tok c2 a) ->
        Grammar state tok (c1 || c2) a
(>>) {c1 = False} act next = thenGrammar act next
(>>) {c1 = True} act next = thenLater act next

||| Sequence two grammars. If either consumes some input, the sequence is
||| guaranteed to consume input. This is an explicitly non-infinite version
||| of `>>=`.
export %inline
seq : {c1,c2 : Bool} ->
      Grammar state tok c1 a ->
      (a -> Grammar state tok c2 b) ->
      Grammar state tok (c1 || c2) b
seq act next = bindGrammar act next

||| Sequence a grammar followed by the grammar it returns.
export %inline
join : {c1,c2 : Bool} ->
       Grammar state tok c1 (Grammar state tok c2 a) ->
       Grammar state tok (c1 || c2) a
join p = bindGrammar p id

||| Allows the result of a grammar to be mapped to a different value.
export
{c : _} ->
Functor (Grammar state tok c) where
  -- The value keeps the bounds of what was parsed; an irrelevant one stays
  -- irrelevant, with no bounds (as `mergeBounds v (irrelevantBounds (f v.val))`).
  map f p
      = MkGrammar $ \inp =>
          case runGrammar p inp of
               Failure com fatal errs => Failure com fatal errs
               Res inp v =>
                 Res inp (if v.isIrrelevant
                             then irrelevantBounds (f v.val)
                             else map f v)

||| Give two alternative grammars. If both consume, the combination is
||| guaranteed to consume.
export
(<|>) : {c1,c2 : Bool} ->
        Grammar state tok c1 ty ->
        Lazy (Grammar state tok c2 ty) ->
        Grammar state tok (c1 && c2) ty
(<|>) x y
    = MkGrammar $ \inp =>
        let com = inp.committed
            inp0 = withCommitted False inp in
        case runGrammar x inp0 of
             Failure com' fatal errs
                => if com' || fatal
                          -- If the alternative had committed, don't try the
                          -- other branch (and reset commit flag)
                     then Failure com fatal errs
                     else case runGrammar y inp0 of
                               Failure com'' fatal' errs' =>
                                 if com'' || fatal'
                                    -- Only add the errors together if the
                                    -- second branch is also non-committed
                                    -- and non-fatal.
                                    then Failure com'' fatal' errs'
                                    else Failure com False (errs ++ errs')
                               Res inp val => Res (withCommitted com inp) val
             -- Successfully parsed the first option, so use the outer commit flag
             Res inp val => Res (withCommitted com inp) val

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
export
(<*>) : {c1, c2 : Bool} ->
        Grammar state tok c1 (a -> b) ->
        Grammar state tok c2 a ->
        Grammar state tok (c1 || c2) b
(<*>) x y = bindGrammar x (\f => map f y)

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

export
act : state -> Grammar state tok False ()
act action
    = MkGrammar $ \inp =>
        Res ({ made.st := inp.made.append inp.made.st action } inp) (irrelevantBounds ())

||| Always succeed with the given value.
export
pure : (val : ty) -> Grammar state tok False ty
pure val = MkGrammar $ \inp => Res inp (irrelevantBounds val)

||| Check whether the next token satisfies a predicate
export
nextIs : String -> (tok -> Bool) -> Grammar state tok False tok
nextIs err f
    = MkGrammar $ \inp =>
        case inp.tokens of
             [] => Failure inp.committed False (Error "End of input" Nothing ::: Nil)
             (x :: xs) =>
               if f x.val
                  then Res inp (removeIrrelevance x)
                  else Failure inp.committed False (Error err (Just x.bounds) ::: Nil)

||| Look at the next token in the input
export
peek : Grammar state tok False tok
peek = nextIs "Unrecognised token" (const True)

||| Succeeds if running the predicate on the next token returns Just x,
||| returning x. Otherwise fails.
export
terminal : String -> (tok -> Maybe a) -> Grammar state tok True a
terminal err f
    = MkGrammar $ \inp =>
        case inp.tokens of
             [] => Failure inp.committed False (Error "End of input" Nothing ::: Nil)
             (x :: xs) =>
               case f x.val of
                    Nothing => Failure inp.committed False (Error err (Just x.bounds) ::: Nil)
                    Just a => Res ({ tokens := xs } inp) (const a <$> x)

-- Fail with a message, at the given location or else at the next token.
failWith : (location : Maybe Bounds) -> (fatal : Bool) -> String ->
           Grammar state tok c ty
failWith location fatal str
    = MkGrammar $ \inp =>
        Failure inp.committed fatal
                (Error str (location <|> firstBounds inp.tokens) ::: Nil)

||| Always fail with a message
export %inline
fail : String -> Grammar state tok c ty
fail = failWith Nothing False

||| Always fail with a message and a location
export %inline
failLoc : Bounds -> String -> Grammar state tok c ty
failLoc b = failWith (Just b) False

||| Fail with no possibility for recovery (i.e.
||| no alternative parsing can succeed).
export %inline
fatalError : String -> Grammar state tok c ty
fatalError = failWith Nothing True

||| Fail with no possibility for recovery (i.e.
||| no alternative parsing can succeed).
export %inline
fatalLoc : Bounds -> String -> Grammar state tok c ty
fatalLoc b = failWith (Just b) True

||| Catch a fatal error
export
try : Grammar state tok c ty -> Grammar state tok c ty
try g
    = MkGrammar $ \inp =>
        case runGrammar g inp of
             -- recover from fatal match but still propagate the 'commit'
             Failure com _ errs => Failure com False errs
             res => res

||| Succeed if the input is empty
export
eof : Grammar state tok False ()
eof = MkGrammar $ \inp =>
        case inp.tokens of
             [] => Res inp (irrelevantBounds ())
             (x :: xs) =>
               Failure inp.committed False
                       (Error "Expected end of input" (Just x.bounds) ::: Nil)

||| Commit to an alternative; if the current branch of an alternative
||| fails to parse, no more branches will be tried
export
commit : Grammar state tok False ()
commit = MkGrammar $ \inp => Res (withCommitted True inp) (irrelevantBounds ())

||| If the parser fails, treat it as a fatal error
export
mustWork : {c : Bool} -> Grammar state tok c ty -> Grammar state tok c ty
mustWork g
    = MkGrammar $ \inp =>
        case runGrammar g inp of
             Failure com' _ errs => Failure com' True errs
             res => res

||| If the parser fails, treat it as a fatal error and explain why
export
mustWorkBecause :
  {c : Bool} -> Bounds -> String ->
  Grammar state tok c ty -> Grammar state tok c ty
mustWorkBecause {c} loc msg p
  = rewrite sym (andSameNeutral c) in
    p <|> fatalLoc loc msg

export
bounds : Grammar state tok c ty -> Grammar state tok c (WithBounds ty)
bounds act
    = MkGrammar $ \inp =>
        case runGrammar act inp of
             Failure com fatal errs => Failure com fatal errs
             Res inp v => Res inp (const v <$> v)

export
mustFailBecause :
  String ->
  Grammar state tok True ty -> Grammar state tok False Unit
mustFailBecause msg p
  = (bounds p >>= \res => fatalLoc {c=False} res.bounds msg) <|> pure ()

export
position : Grammar state tok False Bounds
position
    = MkGrammar $ \inp =>
        case inp.tokens of
             [] => Failure inp.committed False (Error "End of input" Nothing ::: Nil)
             (x :: xs) => Res inp (irrelevantBounds x.bounds)

||| Warn the user
export
withWarning : {c : _} -> String -> Grammar state tok c ty -> Grammar state tok c ty
withWarning warn p
    = rewrite sym $ orFalseNeutral c in
      seq (bounds p) $ \ res =>
      do warning (Just res.bounds) warn
         pure res.val

||| Parse a list of tokens according to the given grammar. If successful,
||| returns a pair of the parse result and the unparsed tokens (the remaining
||| input).
export
parse : {c : Bool} -> (act : Grammar () tok c ty) -> (xs : List (WithBounds tok)) ->
        Either (List1 (ParsingError tok))
               (ParsingWarnings, ty, List (WithBounds tok))
parse act xs
    = case runGrammar act (MkInput (MkMade (<+>) neutral []) False xs) of
           Failure _ _ errs => Left errs
           Res inp v => Right (inp.made.warnings, v.val, inp.tokens)

export
parseWith : Monoid state => {c : Bool} -> (act : Grammar state tok c ty) -> (xs : List (WithBounds tok)) ->
        Either (List1 (ParsingError tok))
               (state, ParsingWarnings, ty, List (WithBounds tok))
parseWith act xs
    = case runGrammar act (MkInput (MkMade (<+>) neutral []) False xs) of
           Failure _ _ errs => Left errs
           Res inp v => Right (inp.made.st, inp.made.warnings, v.val, inp.tokens)
