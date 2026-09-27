||| TEST-SPEC-1: the rule identifiers of docs/architecture/ against the tests.
|||
||| A rule starts with a bold identifier, an optional version, then a period,
||| as in `**TEST-SPEC-1 (p0).` A test references a rule through the
||| identifier in a file or directory name under tests/, or in a
||| `rule: <ID>` comment of a test file (`run`, `expected` and the other
||| files without a suffix, `.idr`, `.mlir`, `.check` and `.sh`). The four
||| checks are the golden tests under tests/spec/:
|||
|||     runtests --spec version       VERSION names an implemented version
|||     runtests --spec duplicates    no rule is defined twice
|||     runtests --spec unknown       every referenced rule exists
|||     runtests --spec untested      the implemented rules without a test
|||
||| Exempt from the last are rules marked *planned*, rules that name review
||| as their check, and rules without a version (principles and reserved
||| rules).
module Spec

import Data.Fin
import Data.List
import Data.List1
import Data.Maybe
import Data.SortedMap
import Data.String
import System
import System.Directory
import System.File

%default covering

||| The profile versions, in order.
order : List String
order = ["p0", "v0", "v1", "v2", "v3"]

upper : Char -> Bool
upper c = c >= 'A' && c <= 'Z'

digit : Char -> Bool
digit c = c >= '0' && c <= '9'

identChar : Char -> Bool
identChar c = upper c || digit c || c == '-'

||| A character of a word, as in the `\w` of Python's regular expressions.
wordChar : Char -> Bool
wordChar c = isAlphaNum c || c == '_' || ord c >= 128

splitLast : List a -> Maybe (List a, a)
splitLast [] = Nothing
splitLast [x] = Just ([], x)
splitLast (x :: xs) = do (init, l) <- splitLast xs; pure (x :: init, l)

||| `[A-Z][A-Z0-9]*(-[A-Z0-9]+)*-[0-9]+`, whole.
identifier : String -> Bool
identifier s =
  case forget (split (== '-') s) of
    (first :: rest) => case (unpack first, splitLast rest) of
      (c :: cs, Just (middle, final)) =>
        upper c && all (\x => upper x || digit x) cs
          && all (\m => m /= "" && all (\x => upper x || digit x) (unpack m)) middle
          && final /= "" && all digit (unpack final)
      _ => False
    [] => False

stripPrefixL : List Char -> List Char -> Maybe (List Char)
stripPrefixL [] s = Just s
stripPrefixL (p :: ps) (c :: cs) = if p == c then stripPrefixL ps cs else Nothing
stripPrefixL _ [] = Nothing

||| `^\s*(?:[-*]\s+)?\*\*<ID>(?: \(<version>\))?\.`: a rule's identifier and
||| version.
export
ruleAt : String -> Maybe (String, Maybe String)
ruleAt line = do
  rest <- stripPrefixL ['*', '*'] (bullet (dropWhile isSpace (unpack line)))
  let (ident, after) = span identChar rest
  guard (identifier (pack ident))
  case after of
    '.' :: _ => Just (pack ident, Nothing)
    ' ' :: '(' :: more =>
      case break (== ')') more of
        (version, ')' :: '.' :: _) => Just (pack ident, Just (pack version))
        _ => Nothing
    _ => Nothing
  where
    bullet : List Char -> List Char
    bullet (b :: s :: more) =
      if (b == '-' || b == '*') && isSpace s then dropWhile isSpace more else b :: s :: more
    bullet cs = cs

public export
record Rule where
  constructor MkRule
  ident : String
  version : Maybe String
  body : List String

||| The rules of one document, each with its text: its line and those after
||| it, up to the next rule or heading.
rulesIn : List String -> List Rule
rulesIn [] = []
rulesIn (l :: ls) = case ruleAt l of
  Nothing => rulesIn ls
  Just (ident, version) =>
    MkRule ident version (l :: takeWhile continues ls) :: rulesIn ls
  where
    continues : String -> Bool
    continues x = isNothing (ruleAt x) && not ("#" `isPrefixOf` x)

readLines : String -> IO (List String)
readLines path = do
  Right text <- readFile path
    | Left err => die "\{path}: \{show err}"
  pure (lines text)

||| Every rule of docs/architecture/, and the identifiers defined twice.
rules : String -> IO (SortedMap String Rule, List String)
rules root = do
  let dir = root ++ "/docs/architecture"
  Right names <- listDir dir
    | Left err => die "\{dir}: \{show err}"
  docs <- for (sort (filter (".md" `isSuffixOf`) names)) $ \n => readLines (dir ++ "/" ++ n)
  pure (foldl add (empty, []) (concatMap rulesIn docs))
  where
    add : (SortedMap String Rule, List String) -> Rule -> (SortedMap String Rule, List String)
    add (found, twice) r =
      (insert r.ident r found, if isJust (lookup r.ident found) then twice ++ [r.ident] else twice)

||| The versions implemented so far, by docs/architecture/VERSION.
implemented : String -> IO (Either String (List String))
implemented root = do
  Right text <- readFile (root ++ "/docs/architecture/VERSION")
    | Left err => pure (Left (show err))
  let version = trim text
  pure $ case findIndex (== version) order of
    Just i => Right (take (S (finToNat i)) order)
    Nothing => Left version

||| Whether `word` occurs in s with no word character on either side.
hasWord : List Char -> List Char -> Bool
hasWord word s = go Nothing s
  where
    go : Maybe Char -> List Char -> Bool
    go _ [] = False
    go before cs@(c :: rest) =
      (not (maybe False wordChar before)
         && maybe False (\after => not (maybe False wordChar (head' after))) (stripPrefixL word cs))
        || go (Just c) rest

||| `(Check|Test): [^\n]*\breview\b` on one line.
reviewed : String -> Bool
reviewed line = any afterMarker [unpack "Check: ", unpack "Test: "]
  where
    firstAfter : List Char -> List Char -> Maybe (List Char)
    firstAfter m [] = Nothing
    firstAfter m cs@(_ :: rest) = case stripPrefixL m cs of
      Just after => Just after
      Nothing => firstAfter m rest

    afterMarker : List Char -> Bool
    afterMarker m = maybe False (hasWord (unpack "review")) (firstAfter m (unpack line))

||| Planned, checked by review, or without a version (principles, reserved).
exempt : Rule -> Bool
exempt r = case r.version of
  Nothing => True
  Just "reserved" => True
  Just _ => any ("*planned*" `isInfixOf`) r.body || any reviewed r.body

inVersions : String -> List String -> Bool
inVersions version versions = case words version of
  [] => False
  (first :: _) =>
    let base = pack (reverse (dropWhile (\c => c == '+' || c == ',') (reverse (unpack first))))
    in if isInfixOf "only" version && last' versions /= Just base
          then False -- superseded by a rule of a later version
          else elem base versions

data Token = Word String | Gap String

tokens : List Char -> List Token
tokens [] = []
tokens (c :: cs) =
  if wordChar c
     then let (w, rest) = span wordChar (c :: cs) in Word (pack w) :: tokens rest
     else let (g, rest) = break wordChar (c :: cs) in Gap (pack g) :: tokens rest

||| The identifiers `\b[A-Z][A-Z0-9]*(?:-[A-Z0-9]+)*-[0-9]+\b` in a name.
export
identifiersIn : String -> List String
identifiersIn s = scan (tokens (unpack s))
  where
    segment : String -> Bool
    segment w = w /= "" && all (\x => upper x || digit x) (unpack w)

    ||| The longest identifier that continues `sofar`, and what follows it.
    extend : List String -> List Token -> Maybe (String, List Token) -> Maybe (String, List Token)
    extend sofar (Gap "-" :: Word w :: more) best =
      if segment w
         then let parts = sofar ++ [w]
                  best' = if all digit (unpack w) then Just (joinBy "-" parts, more) else best
              in extend parts more best'
         else best
    extend _ _ best = best

    scan : List Token -> List String
    scan [] = []
    scan (Gap _ :: ts) = scan ts
    scan (Word w :: ts) =
      case unpack w of
        (c :: cs) =>
          if upper c && all (\x => upper x || digit x) cs
             then case extend [w] ts Nothing of
                    Just (ident, rest) => ident :: scan rest
                    Nothing => scan ts
             else scan ts
        [] => scan ts

||| The identifiers of the `rule: <ID>, <ID>` comments on one line.
export
ruleComments : String -> List String
ruleComments line = go (unpack line)
  where
    more : List Char -> (List String, List Char)
    more (',' :: rest) =
      case span identChar (dropWhile isSpace rest) of
        ([], _) => ([], ',' :: rest)
        (ident, after) => let (ids, left) = more after in (pack ident :: ids, left)
    more cs = ([], cs)

    go : List Char -> List String
    go [] = []
    go cs@(_ :: rest) = case stripPrefixL (unpack "rule: ") cs of
      Just after => case span identChar after of
        ([], _) => go rest
        (ident, left) => let (ids, left') = more left in pack ident :: ids ++ go left'
      Nothing => go rest

||| Python's `PurePath.suffix`.
suffix : String -> String
suffix name =
  case break (== '.') (reverse (unpack name)) of
    (_, []) => ""
    (ext, ['.']) => ""
    ([], _) => ""
    (ext, _) => "." ++ pack (reverse ext)

||| The files whose `rule:` comments count: test scripts, their expectations
||| and fixtures. Test.Golden's `output` files are results, not tests.
scanned : String -> Bool
scanned name = name /= "output" && elem (suffix name) ["", ".idr", ".mlir", ".check", ".sh"]

isDirectory : String -> IO Bool
isDirectory path = do
  Right d <- openDir path
    | Left _ => pure False
  closeDir d
  pure True

||| Every path under tests/, relative to it, but for build directories.
walk : String -> String -> IO (List (String, Bool))
walk root rel = do
  Right names <- listDir (root ++ "/" ++ rel)
    | Left _ => pure []
  found <- for (sort names) $ \n =>
    if n == "build" || n == "__pycache__"
       then pure []
       else do
         let path = if rel == "" then n else rel ++ "/" ++ n
         dir <- isDirectory (root ++ "/" ++ path)
         inner <- if dir then walk root path else pure []
         pure ((path, dir) :: inner)
  pure (concat found)

||| Identifier -> the test paths that reference it.
references : String -> IO (SortedMap String (List String))
references root = do
  let tests = root ++ "/tests"
  paths <- walk tests ""
  found <- for paths $ \(path, dir) => do
    let parts = forget (split (== '/') path)
    let named = concatMap identifiersIn parts
    commented <- if dir || not (maybe False scanned (last' parts))
                    then pure []
                    else do Right text <- readFile (tests ++ "/" ++ path)
                              | Left _ => pure []
                            pure (concatMap ruleComments (lines text))
    pure (map (\i => (i, "tests/" ++ path)) (named ++ commented))
  pure (foldl (\m, (i, p) => insert i (maybe [p] (\ps => if elem p ps then ps else ps ++ [p]) (lookup i m)) m)
              empty (concat found))

report : String -> List String -> IO ()
report title [] = putStrLn (title ++ ": none")
report title xs = do
  putStrLn (title ++ ": " ++ show (length xs))
  traverse_ (\x => putStrLn ("  " ++ x)) xs

||| One check, by name; it prints its result.
export
check : (root : String) -> (name : String) -> IO ()
check root "version" = do
  Right _ <- implemented root
    | Left found => putStrLn ("VERSION is " ++ found ++ ", not one of " ++ joinBy ", " order)
  putStrLn ("VERSION is one of " ++ joinBy ", " order)
check root "duplicates" = do
  (_, twice) <- rules root
  report "rules defined twice" twice
check root "unknown" = do
  (found, _) <- rules root
  refs <- references root
  report "referenced rules that are not in the spec"
    [ i ++ ": " ++ joinBy ", " (sort ps) | (i, ps) <- SortedMap.toList refs, isNothing (lookup i found) ]
check root "untested" = do
  (found, _) <- rules root
  Right versions <- implemented root
    | Left found => putStrLn ("VERSION is " ++ found ++ ", not one of " ++ joinBy ", " order)
  refs <- references root
  report "implemented rules without a test"
    [ r.ident | r <- values found, not (exempt r)
    , maybe False (\v => inVersions v versions) r.version
    , isNothing (lookup r.ident refs) ]
check _ name = die ("unknown spec check: " ++ name)
