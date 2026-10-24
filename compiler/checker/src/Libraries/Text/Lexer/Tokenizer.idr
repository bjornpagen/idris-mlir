-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
||| Tokenizers: the rules that turn text into tokens, tried in order, and a
||| group of tokens a begin lexeme opens and an end lexeme closes, inside
||| which another tokenizer reads.
|||
||| The tokens read so far are a trail, held once, so tokenizing writes it
||| in place; a group that is never closed is cut back off it. Every loop
||| recurses on the characters left, which each token read makes fewer.
module Libraries.Text.Lexer.Tokenizer

import Control.WellFounded
import Data.List
import Data.List1
import Data.Nat

import Libraries.Text.Lexer.Core
import Libraries.Text.PrettyPrint.Prettyprinter
import Libraries.Text.Progress
import Libraries.Text.Token
import Libraries.Text.Trail

import public Libraries.Text.Bounded

%default total

mutual
  ||| The rules of a language's tokens.
  export
  data Tokenizer : Type -> Type where
       Match : Lexer -> (String -> a) -> Tokenizer a
       Compose : Lexer -> (String -> Group a) -> Tokenizer a
       Alt : Tokenizer a -> Lazy (Tokenizer a) -> Tokenizer a

  ||| What a group's begin lexeme opens, made from its text: the token the
  ||| begin makes, the tokenizer of what is inside, the lexer of the end,
  ||| and the token the end makes of its text. Whatever the begin says
  ||| about the rest is computed once, in the function that makes this, and
  ||| reaches the rest as its values.
  public export
  data Group : Type -> Type where
       MkGroup : (opener : a) -> (inside : Inf (Tokenizer a)) ->
                 (end : Lexer) -> (closer : String -> a) -> Group a

||| Alternative rules: the first that reads a token.
export %inline
(<|>) : Tokenizer t -> Lazy (Tokenizer t) -> Tokenizer t
(<|>) = Alt

||| A token made of the text the lexer reads.
export %inline
match : Lexer -> (String -> a) -> Tokenizer a
match = Match

||| A group: its begin lexeme, and what the begin's text opens. The
||| tokenizer inside is made only once the begin has been read, so it may
||| be the tokenizer being defined.
public export %inline %tcinline
compose : (begin : Lexer) -> (opens : String -> Group a) -> Tokenizer a
compose = Compose

||| The rules given, tried in order, each making its token from the text its
||| lexer reads.
export
tokenRules : List1 (Lexer, String -> a) -> Tokenizer a
tokenRules ((l, f) ::: rest) = rulesFrom (Match l f) rest
  where
    -- the rules after `first`
    rulesFrom : Tokenizer a -> List (Lexer, String -> a) -> Tokenizer a
    rulesFrom first [] = first
    rulesFrom first ((l', f') :: more) = Alt first (rulesFrom (Match l' f') more)

||| Why tokenizing stopped: at the end of the input, at a character no rule
||| reads, or in a group whose end never came.
||| @ ComposeNotClosing carries the span of the group's begin lexeme, as
|||                     `(startLine, startCol), (endLine, endCol)`.
public export
data StopReason = EndInput | NoRuleApply | ComposeNotClosing (Int, Int) (Int, Int)

export
Show StopReason where
  show EndInput = "EndInput"
  show NoRuleApply = "NoRuleApply"
  show (ComposeNotClosing start end) = "ComposeNotClosing " ++ show start ++ " " ++ show end

export
Pretty Void StopReason where
  pretty EndInput = pretty "EndInput"
  pretty NoRuleApply = pretty "NoRuleApply"
  pretty (ComposeNotClosing start end) = "ComposeNotClosing" <++> pretty (show start) <++> pretty (show end)

------------------------------------------------------------------------------
-- Tokenizing
------------------------------------------------------------------------------

-- The text of a lexeme, and where it ends.
record Lexeme where
  constructor MkLexeme
  spelling : String
  endLine : Int
  endCol : Int

-- Where `cs` end, read from `line` and `col`: a newline begins the next
-- line, at column 0.
endOf : List Char -> (line, col : Int) -> (Int, Int)
endOf [] line col = (line, col)
endOf ('\n' :: cs) line col = endOf cs (line + 1) 0
endOf (_ :: cs) line col = endOf cs line (col + 1)

-- The `n` characters a lexer read from `input`, begun at `line` and `col`.
lexeme : (n : Nat) -> List Char -> (line, col : Int) -> Lexeme
lexeme n input line col
    = let cs = take n input
          end = endOf cs line col in
          MkLexeme (fastPack cs) (fst end) (snd end)

-- The tokens read so far.
Lexed : Type -> Type
Lexed a = Trail (Located a)

-- What one rule did from `input`: read a token, or a group, and stopped
-- where it says, at fewer characters; read nothing; or opened a group it
-- never closed, whose begin is where it says.
data Step : Type -> List Char -> Type where
  Moved : (1 toks : Lexed a) -> (line, col : Int) -> (rest : List Char) ->
          (0 fewer : Nat.LT (List.length rest) (List.length input)) -> Step a input
  NoRule : (1 toks : Lexed a) -> Step a input
  Unclosed : (1 toks : Lexed a) -> (begin, beginEnd : (Int, Int)) -> Step a input

-- Where tokenizing from `input` stopped, why, and the input from there.
data Ended : Type -> List Char -> Type where
  MkEnded : (1 toks : Lexed a) -> (reason : StopReason) -> (line, col : Int) -> (rest : List Char) ->
            (0 within : Nat.LTE (List.length rest) (List.length input)) -> Ended a input

-- What a rule read, made a token.
matched : (String -> a) -> (input : List Char) -> (line, col : Int) -> (1 toks : Lexed a) ->
          Maybe (Scanned True input) -> Step a input
matched f input line col toks Nothing = NoRule toks
matched f input line col toks (Just (MkScanned n rest fewer))
    = let lx = lexeme n input line col in
          Moved (write (MkLocated (f lx.spelling) (MkBounds line col lx.endLine lx.endCol)) toks)
                lx.endLine lx.endCol rest fewer

-- A group's end, read after what was inside it.
closed : (closer : String -> a) -> (begin, beginEnd : (Int, Int)) -> (line, col : Int) ->
         (r : List Char) -> (0 inside : Nat.LT (List.length r) (List.length input)) ->
         (1 toks : Lexed a) -> Maybe (Scanned True r) -> Step a input
closed closer begin beginEnd line col r inside toks Nothing = Unclosed toks begin beginEnd
closed closer begin beginEnd line col r inside toks (Just (MkScanned n rest fewer))
    = let lx = lexeme n r line col in
          Moved (write (MkLocated (closer lx.spelling) (MkBounds line col lx.endLine lx.endCol)) toks)
                lx.endLine lx.endCol rest (transitive fewer (lteSuccLeft inside))

-- What was inside a group has been read: a group inside it left open is
-- this group's failure too; otherwise the group's end is read where the
-- inside stopped.
closing : (end : Lexer) -> (closer : String -> a) -> (begin, beginEnd : (Int, Int)) ->
          (0 began : Nat.LT (List.length r) (List.length input)) ->
          (1 inner : Ended a r) -> Step a input
closing end closer begin beginEnd began (MkEnded toks (ComposeNotClosing b e) line col rest within)
    = Unclosed toks b e
closing end closer begin beginEnd began (MkEnded toks _ line col rest within)
    = closed closer begin beginEnd line col rest (transitive (LTESucc within) began) toks (scan end rest)

-- What follows a step, ended within the input the step was given.
after : (0 fewer : Nat.LT (List.length rest) (List.length input)) -> (1 e : Ended a rest) -> Ended a input
after fewer (MkEnded toks reason line col r within)
    = MkEnded toks reason line col r (transitive within (lteSuccLeft fewer))

mutual
  -- Tokens read until `stop` matches, the input ends, or no rule reads a
  -- token. Each token read leaves fewer characters, and the recursion is
  -- on them.
  tokenise : (stop : Lexer) -> Tokenizer a -> (input : List Char) -> (line, col : Int) ->
             (1 toks : Lexed a) -> (0 acc : Accessible Nat.LT (List.length input)) -> Ended a input
  tokenise stop t [] line col toks acc = MkEnded toks EndInput line col [] reflexive
  tokenise stop t input line col toks acc = stopOr stop t input line col toks acc (scan stop input)

  -- Where `stop` matched, the end; otherwise one step.
  stopOr : (stop : Lexer) -> Tokenizer a -> (input : List Char) -> (line, col : Int) ->
           (1 toks : Lexed a) -> (0 acc : Accessible Nat.LT (List.length input)) ->
           Maybe (Scanned True input) -> Ended a input
  stopOr stop t input line col toks acc (Just _) = MkEnded toks EndInput line col input reflexive
  stopOr stop t input line col toks acc Nothing = stepFrom stop t input line col (measured toks) acc

  -- One step, from the tokens read so far, measured so that a group left
  -- open is cut back off them.
  stepFrom : (stop : Lexer) -> Tokenizer a -> (input : List Char) -> (line, col : Int) ->
             (1 marked : Stepped (Lexed a) Nat) -> (0 acc : Accessible Nat.LT (List.length input)) ->
             Ended a input
  stepFrom stop t input line col (MkStepped toks mark) acc@(Access rec)
      = afterStep stop t input line col mark rec (step t input line col toks acc)

  afterStep : (stop : Lexer) -> Tokenizer a -> (input : List Char) -> (line, col : Int) -> (mark : Nat) ->
              (0 rec : (y : Nat) -> Nat.LT y (List.length input) -> Accessible Nat.LT y) ->
              (1 res : Step a input) -> Ended a input
  afterStep stop t input line col mark rec (Moved toks line' col' rest fewer)
      = after fewer (tokenise stop t rest line' col' toks (rec (List.length rest) fewer))
  afterStep stop t input line col mark rec (NoRule toks)
      = MkEnded toks NoRuleApply line col input reflexive
  afterStep stop t input line col mark rec (Unclosed toks begin beginEnd)
      = MkEnded (cutTo mark toks) (ComposeNotClosing begin beginEnd) line col input reflexive

  -- The first rule that reads from `input`.
  step : Tokenizer a -> (input : List Char) -> (line, col : Int) -> (1 toks : Lexed a) ->
         (0 acc : Accessible Nat.LT (List.length input)) -> Step a input
  step (Match l f) input line col toks acc = matched f input line col toks (scan l input)
  step (Compose begin opens) input line col toks (Access rec)
      = opened opens input line col toks rec (scan begin input)
  step (Alt t1 t2) input line col toks acc = orNext t2 input line col acc (step t1 input line col toks acc)

  -- The next rule, where the first read nothing.
  orNext : Lazy (Tokenizer a) -> (input : List Char) -> (line, col : Int) ->
           (0 acc : Accessible Nat.LT (List.length input)) -> (1 res : Step a input) -> Step a input
  orNext t2 input line col acc (NoRule toks) = step t2 input line col toks acc
  orNext t2 input line col acc res = res

  -- A group's begin lexeme read: its token, then what is inside, from
  -- fewer characters, then its end.
  opened : (String -> Group a) -> (input : List Char) -> (line, col : Int) -> (1 toks : Lexed a) ->
           (0 rec : (y : Nat) -> Nat.LT y (List.length input) -> Accessible Nat.LT y) ->
           Maybe (Scanned True input) -> Step a input
  opened opens input line col toks rec Nothing = NoRule toks
  opened opens input line col toks rec (Just (MkScanned n rest fewer))
      = let lx = lexeme n input line col in
            inGroup (opens lx.spelling) (line, col) (lx.endLine, lx.endCol) rest fewer toks
                    (rec (List.length rest) fewer)

  -- Inside a group whose begin ended at `beginEnd`.
  inGroup : Group a -> (begin, beginEnd : (Int, Int)) -> (rest : List Char) ->
            (0 fewer : Nat.LT (List.length rest) (List.length input)) -> (1 toks : Lexed a) ->
            (0 acc : Accessible Nat.LT (List.length rest)) -> Step a input
  inGroup (MkGroup opener inside end closer) begin beginEnd rest fewer toks acc
      = closing end closer begin beginEnd fewer
          (tokenise end inside rest (fst beginEnd) (snd beginEnd)
                    (write (MkLocated opener (MkBounds (fst begin) (snd begin) (fst beginEnd) (snd beginEnd))) toks)
                    acc)

-- The tokens and where tokenizing stopped, the input from there as text.
finish : Ended a input -> (List (Located a), (StopReason, Int, Int, String))
finish (MkEnded toks reason line col rest _) = (contents toks, (reason, line, col, fastPack rest))

||| The tokens the tokenizer reads from the string, stopping where `stop`
||| matches, and why and where it stopped, with the rest of the string.
export
lexTo : (stop : Lexer) -> Tokenizer a -> String -> (List (Located a), (StopReason, Int, Int, String))
lexTo stop t str
    = let input = fastUnpack str in
          finish (tokenise stop t input 0 0 blank (wellFounded (List.length input)))

||| The tokens the tokenizer reads from the string, and why and where it
||| stopped, with the rest of the string.
export
lex : Tokenizer a -> String -> (List (Located a), (StopReason, Int, Int, String))
lex = lexTo fail
