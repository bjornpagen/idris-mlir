-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
||| Parser combinators: a grammar reads tokens and gives a value.
|||
||| `Grammar state tok n r c a` reads `tok`s, keeps a `state` and gives an
||| `a`; `n` bounds the tokens left wherever it runs, `r` is `True` when it
||| runs only once a token has been read since the parse stood at `n`, and
||| `c` is `True` when every success reads a token. A grammar is a function
||| of the parse's input, which it takes once and gives back, so the input
||| is updated in place. The API:
|||
||| - Sequence: `>>=` and `>>` (do notation), `<*>`, `<*`, `*>`, `map` and
|||   `<$>` (a grammar is a `Functor`), `pure`. A sequence consumes if
|||   either part does, and its second part runs below the bound if the
|||   first consumes. `>>`'s second grammar is made only once the first has
|||   succeeded.
||| - Recursion: a grammar names a grammar, itself among them, through a
|||   `Box`, by `call`, which runs only below the bound, so only after a
|||   token has been read; `fixpoint` ties a family of grammars to the box
|||   of itself. `later` and `onward` run a grammar where more is known to
|||   have been read.
||| - Choice: `<|>`, `<||>` (each branch's value tagged), `option`,
|||   `optional`, `choice`, `choiceMap`. A choice consumes if every branch
|||   does. A choice needs the state to `Backtrack`: `()` and a `Trail` do.
||| - Repetition, each recursing on the tokens left, which a consuming
|||   grammar's type says are fewer: `some`, `many`, `sepBy`, `sepBy1`, and
|||   `entries`, a block's entries, each chosen by a seed the last gave.
||| - Tokens: `terminal`, `terminalAt`, `match` (a `Token k` of a kind,
|||   giving its text), `nextIs`, `peek`, `eof`, `position`, `location`,
|||   `column`.
||| - Bounds: `bounds p` gives `p`'s value with the bounds of the tokens it
|||   read, `Irrelevant` if it read none.
||| - Failure: `fail`, `failLoc`, `fatalError`, `fatalLoc`, `commit`,
|||   `try`, `mustWork`, `mustWorkBecause`, `mustFailBecause`, `when`,
|||   `unless`.
||| - State and warnings: `updateState` takes the state at quantity 1 and
|||   gives it back, `Stepped`; `withWarning`.
||| - Running: `parseWith` and `parse`, over the `columns` of a lexer's
|||   tokens, of a grammar had at every bound.
|||
||| What a parse means, stated once:
|||
||| - A grammar runs from where the parse stands and succeeds, with its
|||   value and the tokens it left, or fails, with its errors, fatally or
|||   not. A sequence runs its second part from where the first stopped,
|||   and fails as the first part to fail.
||| - `commit` marks the branch the innermost enclosing alternative is
|||   trying as past a commit point.
||| - `p <|> q` runs `p`, uncommitted. If `p` succeeds, so does the
|||   alternative. If `p` fails past a commit point or fatally, so does the
|||   alternative. Otherwise `q` runs from where `p` began, the state and
|||   the warnings put back as they were, uncommitted; if `q` fails past a
|||   commit point or fatally, the alternative fails as `q` did, and
|||   otherwise it fails with `p`'s errors and then `q`'s. Whatever leaves
|||   the alternative, but `q`'s failure past a commit point or a fatal
|||   one, is as committed as the parse was where the alternative began.
||| - `try p` makes `p`'s fatal failure one an alternative recovers from;
|||   `mustWork p` makes any failure of `p` fatal.
||| - `many p` is, at each round, `p` followed by the rounds after it, or
|||   else no more rounds: an alternative per round, as above.
||| - A failure is located where it says, or else at the next token; at the
|||   end of the input, nowhere.
||| - `bounds p` is from the first token `p` read to the last.
||| - Warnings come in the order given; a branch that fails takes its
|||   warnings and its steps of the state with it.
||| - `call box pick` runs, where the parse stands, the grammar `pick` takes
|||   of what the box holds there.
module Libraries.Text.Parser

import Data.Bool
import Data.Nat
import public Data.List1

import public Libraries.Text.Parser.Core
import public Libraries.Text.Token

%default total

%hide Prelude.(>>)
%hide Prelude.(>>=)

||| A token of the kind given, giving its text.
export
match : Eq k => (kind : k) -> Grammar state (Token k) bound r True String
match k = terminal "Unrecognised input" ofKind
  where
    ofKind : Token k -> Maybe String
    ofKind t = if t.kind == k then Just t.text else Nothing

||| The grammar, or else the value given, reading nothing. May match the
||| empty input.
export
option : Backtrack mark state => {0 c : Bool} ->
         (def : a) -> (p : Grammar state tok bound r c a) ->
         Grammar state tok bound r False a
option def p = rewrite sym (andFalseFalse c) in p <|> pure def

||| The grammar's value, or else nothing, reading nothing.
export
optional : Backtrack mark state => {0 c : Bool} ->
           (p : Grammar state tok bound r c a) ->
           Grammar state tok bound r False (Maybe a)
optional p = option Nothing (map Just p)

export infixr 2 <||>
||| Two alternative grammars, each one's value tagged with which it was. If
||| both consume, so does the choice.
export
(<||>) : Backtrack mark state => {0 c1, c2 : Bool} ->
         Grammar state tok bound r c1 a -> Lazy (Grammar state tok bound r c2 b) ->
         Grammar state tok bound r (c1 && c2) (Either a b)
p <||> q = map Left p <|> map Right q

||| The grammar a function makes of each element, tried in turn until one
||| succeeds. Fails if there are none.
export
choiceMap : Backtrack mark state => {0 c : Bool} ->
            (a -> Grammar state tok bound r c b) ->
            Foldable t => t a ->
            Grammar state tok bound r c b
choiceMap f xs = foldr (\x, acc => rewrite sym (andSameNeutral c) in f x <|> acc)
                       (fail "No more options") xs

||| Each grammar tried in turn until one succeeds. Fails if there are none.
export
choice : Backtrack mark state => Foldable t => {0 c : Bool} ->
         t (Grammar state tok bound r c a) ->
         Grammar state tok bound r c a
choice = choiceMap id

||| One or more of `p`, each after the first following a separator, which
||| reads a token: so each `p` after the first runs below the bound, and
||| what follows the first runs where it does.
export
sepBy1 : Backtrack mark state => {0 c : Bool} ->
         (sep : Grammar state tok bound r True s) ->
         (p : Grammar state tok bound r c a) ->
         Grammar state tok bound r c (List1 a)
sepBy1 sep p = rewrite sym (orFalseNeutral c) in
                       p >>= \x => map (x :::) (onward {d = c} (many (sep *> later p)))

||| None or more of `p`, each after the first following a separator. May
||| match the empty input.
export
sepBy : Backtrack mark state => {0 c : Bool} ->
        (sep : Grammar state tok bound r True s) ->
        (p : Grammar state tok bound r c a) ->
        Grammar state tok bound r False (List a)
sepBy sep p = option [] (forget <$> sepBy1 sep p)

||| The grammar, any failure of it made fatal, with `msg` at `loc`.
export
mustWorkBecause : Backtrack mark state => {0 c : Bool} ->
                  Maybe Bounds -> String ->
                  Grammar state tok bound r c ty -> Grammar state tok bound r c ty
mustWorkBecause loc msg p = rewrite sym (andSameNeutral c) in
                                    p <|> fatalLoc loc msg

||| A fatal failure, with `msg` at its bounds, where `p` succeeds; nothing
||| read where it does not.
export
mustFailBecause : Backtrack mark state =>
                  String -> Grammar state tok bound r True ty -> Grammar state tok bound r False ()
mustFailBecause msg p = (bounds p >>= \res => fatalLoc {c = False} res.bounds msg) <|> pure ()

||| Where the next token begins: its line and column.
export
location : Grammar state tok bound r False (Int, Int)
location = startBounds <$> position

||| The column the next token begins at.
export
column : Grammar state tok bound r False Int
column = snd <$> location

||| The grammar where the condition holds, otherwise nothing.
public export
when : Bool -> Lazy (Grammar state tok bound r False ()) -> Grammar state tok bound r False ()
when True y = y
when False y = pure ()

||| The grammar where the condition does not hold, otherwise nothing.
public export %inline
unless : Bool -> Lazy (Grammar state tok bound r False ()) -> Grammar state tok bound r False ()
unless = when . not
