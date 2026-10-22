-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| A run's verdict, once harness/one.sh has run a test and kept its output:
|||
|||     runtests --verdict <results> <test> <directory> <kind> <output> <stderr>
|||
||| The expectation is a target-specific expected.<name> where one exists,
||| named as a `targets` file names this host (its architecture, x86-64 or
||| aarch64, or its operating system, macos or linux), else `expected`, else
||| the kind's own, harness/kinds/<kind>.expected, for a kind that fixes what
||| a good run prints (a fixture: every RUN line holds). A test whose output
||| is the target's own (a page size, the symbols a runtime needs) then
||| holds on each target, with one expectation per target, instead of a skip
||| or a loose check. The output must be the expectation byte for byte. The
||| verdict, and on a failure the difference from the expectation (or the
||| whole output, when there is none) and the first lines the run wrote on
||| stderr, go to stdout in one piece, and the test is appended to the
||| results' `passed` or `failed`.
module Verdict

import Data.List
import Data.List1
import Data.Maybe
import Data.SortedMap
import Data.String
import System
import System.File

import Files
import Harness

%default covering

------------------------------------------------------------------------------
-- A difference, as diff -u writes one
------------------------------------------------------------------------------

||| A line of a file, with whether a line's end follows it: a last line
||| without one differs from the same text with one.
record Line where
  constructor MkLine
  text : String
  ended : Bool

Eq Line where
  a == b = a.text == b.text && a.ended == b.ended

linesOf : String -> List Line
linesOf text = mark (forget (split (== '\n') text))
  where
    mark : List String -> List Line
    mark [] = []
    mark [final] = if final == "" then [] else [MkLine final False]
    mark (l :: ls) = MkLine l True :: mark ls

||| An edit of the expectation into the output, a line at a time.
data Edit = Keep Line | Delete Line | Insert Line

indexedFrom : Int -> List a -> SortedMap Int a
indexedFrom _ [] = empty
indexedFrom i (x :: xs) = insert i x (indexedFrom (i + 1) xs)

||| The shortest edit of the middle two sequences, by Myers's walk of its
||| diagonals: each round reaches one edit further on every diagonal, and
||| the walk back through the rounds' furthest points reads the edits off.
||| It ends: a round reaches each end of both after at most as many rounds
||| as the two have lines.
myers : List Line -> List Line -> List Edit
myers as bs = search 0 (SortedMap.singleton 1 0) []
  where
    xs : SortedMap Int Line
    xs = indexedFrom 0 as

    ys : SortedMap Int Line
    ys = indexedFrom 0 bs

    n : Int
    n = cast (length as)

    m : Int
    m = cast (length bs)

    at : SortedMap Int Int -> Int -> Int
    at v k = fromMaybe 0 (lookup k v)

    same : Int -> Int -> Bool
    same x y = case (lookup x xs, lookup y ys) of
      (Just a, Just b) => a == b
      _ => False

    snake : Int -> Int -> Int
    snake x y = if same x y then snake (x + 1) (y + 1) else x

    -- The diagonal a round's path to diagonal k comes from: down from
    -- k + 1, or across from k - 1.
    from : SortedMap Int Int -> Int -> Int -> Int
    from v d k = if k == negate d || (k /= d && at v (k - 1) < at v (k + 1)) then k + 1 else k - 1

    round : Int -> Int -> SortedMap Int Int -> SortedMap Int Int -> Either (SortedMap Int Int) (SortedMap Int Int)
    round d k start v =
      if k > d then Right v else
        let x0 = if from start d k == k + 1 then at start (k + 1) else at start (k - 1) + 1
            x = snake x0 (x0 - k)
            v' = insert k x v
        in if x >= n && x - k >= m then Left v' else round d (k + 2) start v'

    keepAt : Int -> List Edit -> List Edit
    keepAt i acc = maybe acc (\l => Keep l :: acc) (lookup i xs)

    diagonal : Int -> Int -> List Edit -> List Edit
    diagonal x y acc = if x > 0 && y > 0 then diagonal (x - 1) (y - 1) (keepAt (x - 1) acc) else acc

    snakeBack : Int -> Int -> Int -> Int -> List Edit -> (Int, Int, List Edit)
    snakeBack x y px py acc =
      if x > px && y > py then snakeBack (x - 1) (y - 1) px py (keepAt (x - 1) acc) else (x, y, acc)

    back : Int -> Int -> Int -> List (SortedMap Int Int) -> List Edit -> List Edit
    back x y _ [] acc = diagonal x y acc
    back x y d (v :: older) acc =
      if d == 0 then diagonal x y acc else
        let k = x - y
            prevK = from v d k
            prevX = at v prevK
            prevY = prevX - prevK
            (x1, y1, acc1) = snakeBack x y prevX prevY acc
            acc2 = if x1 == prevX
                      then maybe acc1 (\l => Insert l :: acc1) (lookup (y1 - 1) ys)
                      else maybe acc1 (\l => Delete l :: acc1) (lookup (x1 - 1) xs)
        in back prevX prevY (d - 1) older acc2

    search : Int -> SortedMap Int Int -> List (SortedMap Int Int) -> List Edit
    search d v history = case round d (negate d) v v of
      Left _ => back n m d (v :: history) []
      Right v' => search (d + 1) v' (v :: history)

||| The edit of one file into another: their common start and end kept,
||| and the shortest edit of what lies between.
editOf : List Line -> List Line -> List Edit
editOf as bs =
  let (start, as1, bs1) = common [<] as bs
      (end, as2, bs2) = common [<] (reverse as1) (reverse bs1)
  in map Keep start ++ middle (reverse as2) (reverse bs2) ++ map Keep (reverse end)
  where
    common : SnocList Line -> List Line -> List Line -> (List Line, List Line, List Line)
    common acc (a :: as') (b :: bs') = if a == b then common (acc :< a) as' bs' else (acc <>> [], a :: as', b :: bs')
    common acc as' bs' = (acc <>> [], as', bs')

    middle : List Line -> List Line -> List Edit
    middle [] ys = map Insert ys
    middle xs [] = map Delete xs
    middle xs ys = myers xs ys

||| An edit with the lines of each file before it.
record Placed where
  constructor MkPlaced
  edit : Edit
  expectedBefore : Nat
  outputBefore : Nat

placed : List Edit -> List Placed
placed = go 0 0
  where
    go : Nat -> Nat -> List Edit -> List Placed
    go _ _ [] = []
    go a b (e@(Keep _) :: es) = MkPlaced e a b :: go (S a) (S b) es
    go a b (e@(Delete _) :: es) = MkPlaced e a b :: go (S a) b es
    go a b (e@(Insert _) :: es) = MkPlaced e a b :: go a (S b) es

changed : Edit -> Bool
changed (Keep _) = False
changed _ = True

||| The lines of context around a change; two changes with no more than
||| twice as many lines between them share a hunk.
context : Nat
context = 3

||| The changes' positions grouped into hunks: each group's first and last.
grouped : List Nat -> List (Nat, Nat)
grouped [] = []
grouped (c :: cs) = go c c cs
  where
    go : Nat -> Nat -> List Nat -> List (Nat, Nat)
    go first lastOne [] = [(first, lastOne)]
    go first lastOne (c' :: rest) =
      if minus c' lastOne <= S (2 * context) then go first c' rest else (first, lastOne) :: go c' c' rest

||| A hunk's range of one file, as diff -u writes it: its first line and its
||| count, the count left out when it is one, and an empty range named by
||| the line before it.
range : (before, count : Nat) -> String
range before (S Z) = show (S before)
range before Z = show before ++ ",0"
range before count = show (S before) ++ "," ++ show count

editLines : Edit -> List String
editLines e =
  let (mark, l) = case e of
                    Keep x => (" ", x)
                    Delete x => ("-", x)
                    Insert x => ("+", x)
  in (mark ++ l.text) :: (if l.ended then [] else ["\\ No newline at end of file"])

||| The difference between two files as `diff -u` writes it, without its
||| two lines naming the files: each hunk's header, then its lines.
unifiedDiff : List Line -> List Line -> List String
unifiedDiff as bs =
  let edits = placed (editOf as bs)
      positions = [p | (p, x) <- zip [0 .. length edits] edits, changed x.edit]
  in concatMap (hunk edits) (grouped positions)
  where
    hunk : List Placed -> (Nat, Nat) -> List String
    hunk edits (first, lastOne) =
      let start = minus first context
          items = take (S (minus (min (minus (length edits) 1) (lastOne + context)) start)) (drop start edits)
          counted = \f => length (filter f items)
      in case items of
           [] => []
           (top :: _) =>
             ("@@ -" ++ range top.expectedBefore (counted (\x => not (isInsert x.edit)))
              ++ " +" ++ range top.outputBefore (counted (\x => not (isDelete x.edit))) ++ " @@")
             :: concatMap (editLines . (.edit)) items
      where
        isInsert : Edit -> Bool
        isInsert (Insert _) = True
        isInsert _ = False

        isDelete : Edit -> Bool
        isDelete (Delete _) = True
        isDelete _ = False

------------------------------------------------------------------------------
-- The verdict
------------------------------------------------------------------------------

||| The file a run's output is held to (above).
expectationOf : (harness, directory, kind : String) -> (hosts : List String) -> IO String
expectationOf harness directory kind hosts = do
  let common = directory ++ "/expected"
  let kinds = harness ++ "/kinds/" ++ kind ++ ".expected"
  hasCommon <- exists common
  hasKind <- exists kinds
  let fallback = if not hasCommon && hasKind then kinds else common
  pick fallback hosts
  where
    pick : String -> List String -> IO String
    pick fallback [] = pure fallback
    pick fallback (h :: hs) = do
      let specific = directory ++ "/expected." ++ h
      there <- exists specific
      if there then pure specific else pick fallback hs

||| `--verdict <results> <test> <directory> <kind> <output> <stderr>`.
export
verdict : (results, test, directory, kind, output, stderr : String) -> IO ()
verdict results test directory kind output stderr = do
  Just root <- getEnv "IDRIS_MLIR_ROOT"
    | Nothing => die "runtests: IDRIS_MLIR_ROOT is unset; run the tests through make"
  Just hosts <- getEnv "IDRIS_MLIR_HOST_NAMES"
    | Nothing => die "runtests: IDRIS_MLIR_HOST_NAMES is unset; run the tests through make"
  expected <- expectationOf (root ++ "/harness") directory kind (words hosts)
  there <- exists expected
  ours <- bytesIfThere output
  theirs <- if there then bytesIfThere expected else pure ""
  if there && ours == theirs
     then finish "passed" (test ++ ": success\n")
     else do
       outText <- fromMaybe "" <$> readIfThere output
       difference <- if there
         then do
           expectedText <- fromMaybe "" <$> readIfThere expected
           pure (unlines (("- " ++ expected ++ ", + " ++ output ++ ":") :: unifiedDiff (linesOf expectedText) (linesOf outText)))
         else pure (expected ++ ": missing; the output, " ++ output ++ ", is:\n" ++ outText)
       wrote <- nonEmpty stderr
       errors <- if wrote
         then (\ls => unlines (("stderr of " ++ test ++ ":") :: indented ls)) <$> firstLines 40 [stderr]
         else pure ""
       finish "failed" (test ++ ": FAILURE\n" ++ difference ++ errors ++ "\n")
  where
    finish : String -> String -> IO ()
    finish list report = do
      putStr report
      ignore (appendFile (results ++ "/" ++ list) (test ++ "\n"))
