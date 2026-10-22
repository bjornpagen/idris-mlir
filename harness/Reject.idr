-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| A program the compiler refuses by one rule: its header, read once into
||| the rule (one of the specification's, Facts.idr), the line and the
||| words its message holds; the compilation's report, read once into its
||| verdict and its errors, each with its rule; and the one comparison of
||| the two (lib/profile.sh, profile_reject):
|||
|||     runtests --reject <test> <report> <output>
|||
||| prints a line for the rule, the line and, when the header has one, the
||| message (found anywhere in <output>, what the compilation printed), and
||| exits 1 when any of them is not what the header says. A script that
||| expects a refusal by a rule without a header to hold it (the registry's
||| broken entries, lib/profile.sh; the prelude's escape hatches,
||| lib/prelude.sh) asks the same reader:
|||
|||     runtests --refused-by <report> <rule> [<file>]
module Reject

import Data.List
import Data.List1
import Data.Maybe
import Data.String
import System

import Facts
import Files

import IdrisMLIR.Spec.Core.Rules
import IdrisMLIR.Spec.Core.Verdict

%default covering

------------------------------------------------------------------------------
-- The header
------------------------------------------------------------------------------

||| What a refused program's first lines say of its refusal.
public export
record Header where
  constructor MkHeader
  rule : SomeRule
  line : Nat
  message : Maybe String

||| The value of `-- <field>: <value>` on a header line.
fieldOf : String -> String -> Maybe String
fieldOf field text = do
  rest <- stripPrefix "--" text
  value <- stripPrefix (field ++ ":") (trim rest)
  pure (trim value)
  where
    stripPrefix : String -> String -> Maybe String
    stripPrefix p s = if isPrefixOf p s then Just (pack (drop (length p) (unpack s))) else Nothing

||| `<phrase>, line <n>`, split at its last comma.
expectation : String -> Either String (String, Nat)
expectation text =
  case break (== ',') (reverse (unpack text)) of
    (after, ',' :: before) =>
      case words (pack (reverse after)) of
        ["line", n] => maybe (Left "no line number") (\l => Right (pack (reverse before), l)) (parsePositive n)
        _ => Left "no `line <n>` after the comma"
    _ => Left "no comma before the line"

||| The header of a refused program's Main.idr: its first line names the
||| rule and the line, and the next may name words of the message.
export
headerOf : String -> Either String Header
headerOf text =
  let ls = lines text
      first = fromMaybe "" (head' ls)
      second = fromMaybe "" (head' (drop 1 ls))
  in do
    expected <- maybe (Left "the first line must be '-- expect: <rule>, line <n>'") Right (fieldOf "expect" first)
    (phrase, line) <- expectation expected
    rule <- maybe (Left (phrase ++ " is no rule's phrase")) Right (ruleNamed phrase)
    pure (MkHeader rule line (fieldOf "message" second))

------------------------------------------------------------------------------
-- The report
------------------------------------------------------------------------------

||| Where in the source an error is: the file and the line of its first
||| file location.
public export
record Place where
  constructor MkPlace
  file : String
  line : Nat

||| An error of the report: the rule it refuses by, if any, and its place,
||| if it names one.
public export
record Refusal where
  constructor MkRefusal
  rule : Maybe SomeRule
  place : Maybe Place

||| The report idris-mlir writes under --report: `verdict: <name>`, a
||| `diagnostic: <severity> <rule> <file:line>` line per diagnostic (a field
||| it lacks written `-`), and statistics, which this reads no part of. A
||| report with no verdict, or one no verdict of the specification's
||| spells, has none.
public export
record Report where
  constructor MkReport
  verdict : Maybe CompilerVerdict
  errors : List Refusal

||| A location `<file>:<line>`, split at its last colon; a field the
||| diagnostic lacks (`-`) has no colon, and so no place.
placeOf : String -> Maybe Place
placeOf loc = case break (== ':') (reverse (unpack loc)) of
  (digits, ':' :: file) => MkPlace (pack (reverse file)) <$> parsePositive (pack (reverse digits))
  _ => Nothing

refusalOf : String -> Maybe Refusal
refusalOf text = case words text of
  ["diagnostic:", "error", rule, loc] =>
    Just (MkRefusal (if rule == "-" then Nothing else ruleOfField rule) (placeOf loc))
  _ => Nothing

||| A report's text, read once into its record: the one reader of the
||| report, which every comparison with one asks.
export
reportOf : String -> Report
reportOf text =
  let ls = lines text in
  MkReport (head' (mapMaybe stripVerdict ls) >>= readVerdict) (mapMaybe refusalOf ls)
  where
    stripVerdict : String -> Maybe String
    stripVerdict l = if isPrefixOf "verdict:" l then Just (pack (drop 8 (unpack l))) else Nothing

------------------------------------------------------------------------------
-- The comparison
------------------------------------------------------------------------------

||| Whether a refusal is by the header's rule.
byRule : SomeRule -> Refusal -> Bool
byRule wanted r = maybe False (\got => phraseOf got == phraseOf wanted) r.rule

||| A refusal by a rule of ours: an error by no rule, or by a rule Idris's
||| own errors are not reported under.
ours : Refusal -> Bool
ours r = case map judge r.rule of
  Just Idris => False
  _ => True

||| The lines of the comparison, and whether every one holds.
compareWith : Header -> Report -> (output : String) -> (List String, Bool)
compareWith h report output =
  let phrase = phraseOf h.rule
      unexpected : String
      unexpected = "unsupported (" ++ phrase ++ "): expected once, among "
                   ++ show (length (filter ours report.errors)) ++ " unsupported errors"
      ruleLine : (String, Bool)
      ruleLine = case (report.verdict, report.errors) of
        (Just VerdictInternal, _) => (phrase ++ ": an internal error, not a rejection", False)
        (_, [only]) => if byRule h.rule only then ("unsupported (" ++ phrase ++ "): the only error", True)
                       else (unexpected, False)
        _ => (unexpected, False)
      reportedLine : Maybe Nat
      reportedLine = map (.line) (head' report.errors >>= (.place))
      lineLine : (String, Bool)
      lineLine = if reportedLine == Just h.line then ("line: as the header says", True)
                 else ("line: " ++ maybe "none" show reportedLine ++ " reported, the header says " ++ show h.line, False)
      messageLine : List (String, Bool)
      messageLine = case h.message of
        Nothing => []
        Just m => if isInfixOf m output then [("message: as the header says", True)]
                  else [("message: not in the output: " ++ m, False)]
      checks = ruleLine :: lineLine :: messageLine
  in (map fst checks, all snd checks)

||| `--reject <test> <report> <output>`.
export
reject : (test : String) -> (report : String) -> (output : String) -> IO ()
reject test reportPath outputPath = do
  main <- readOrDie (test ++ "/Main.idr")
  let Right header = headerOf main
    | Left why => do putStrLn why; exitFailure
  report <- reportOf <$> fromMaybe "" <$> readIfThere reportPath
  output <- bytesIfThere outputPath
  let (shown, holds) = compareWith header report output
  traverse_ putStrLn shown
  if holds then exitSuccess else exitFailure

||| Where a refusal's errors must be: anywhere, or at places in one file
||| (the probe's own module, so the refusal is of its use and not of
||| something it reaches).
public export
data Within = Anywhere | InFile String

within : Within -> Refusal -> Bool
within Anywhere _ = True
within (InFile f) r = map (.file) r.place == Just f

||| `--refused-by <report> <rule> [<file>]`: the compilation was refused,
||| with at least one error, and every error is by the rule (named by its
||| phrase, read into the specification's rule once) and within the file
||| when one is named; the status is 1 when not. A phrase that is no rule's
||| fails the check and is named on stderr, which a failing test shows, so
||| a stale phrase is found rather than read as a refusal not made.
export
refusedBy : (report : String) -> (phrase : String) -> Within -> IO ()
refusedBy reportPath phrase area = do
  let Just rule = ruleNamed phrase
    | Nothing => die (phrase ++ " is no rule's phrase")
  report <- reportOf <$> fromMaybe "" <$> readIfThere reportPath
  case report.verdict of
    Just VerdictRefused =>
      if not (null report.errors) && all (\r => byRule rule r && within area r) report.errors
         then exitSuccess else exitFailure
    _ => exitFailure
