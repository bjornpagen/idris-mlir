-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Table-driven integer semantics over every fixed-width integer type: for
||| each builtin of the table (Prims.idr) of two values of a fixed width,
||| and for each fixed width's casts to the others, every pair of a set of
||| operands, with the value the builtin gives or the crash its guard meets,
||| computed here from what each builtin means and from the guard its op
||| states, not from the compiler.
|||
||| A test's cases inside their guards are the `Prog` module of an ordinary
||| end-to-end fixture, whose Main.idr prints `Prog.result`: 0 when every
||| case agrees with the table, and otherwise the number of the first case
||| that disagrees. They run twice, in two programs of one table. In one,
||| their operands are written in the program, so this compiler computes
||| each case while it compiles. In the other, every operand and the value
||| each case must give are read from standard input, so only the compiled
||| program's own arithmetic can answer: the expansion of each operation
||| into code is checked as well as its folder, and a slip in one that the
||| other lacks fails one program only.
|||
||| A case outside its builtin's guard crashes, which ends the program, so
||| each is a case of its own of the second program: its input is the
||| cases' inside, but for its group's first row, which holds its operands;
||| its run must end by the crash of its guard's cause, the runtime's line
||| naming the site of the builtin's application in Prog.
|||
||| A test is one fixed-width type and one builtin of two values of it, or
||| the type's casts to every other fixed width: `prim-<type>-<word>`, the
||| type in lower case and the word as Idris spells the builtin
||| (`prim-int8-add`, `prim-bits64-cast`). They run as
||| `tests/semantics@<name>`, one test of the runner per name
||| (harness/Main.idr), whose `run` asks the runner for the programs and
||| the cases of the second:
|||
|||     runtests --sem-program written|stdin prim-<type>-<word>
|||     runtests --sem-cases prim-<type>-<word> <cases-dir>
|||
||| `runtests --sem-expected <name>` prints the stdout the written program
||| must print, the value `result` ends with when every case agrees, so that
||| the value is stated once, here.
module Sem

import Prelude
import Data.List
import Data.List1
import Data.Maybe
import Data.SortedMap
import Data.String
import System.Directory
import System.File

import Facts
import Prims

import IdrisMLIR.Spec.Ops.Numeric
import IdrisMLIR.Spec.Runtime.Endings

%default covering

||| A fixed-width type as a type.
fixedTy : FixedTy -> Ty
fixedTy f = TIntegral (Sized f)

||| The operands of a type's tests: its edges and the values beside them,
||| small values of both signs, and the shift amounts at its width (below,
||| at and past it).
operands : FixedTy -> List Integer
operands f =
  let w = width f
      (lo, hi) = bounds f
      bits = natToInteger w.bits
      (edges, small) = the (List Integer, List Integer) $ case w.signedness of
        Signed => ([lo, lo + 1, -1, 0, 1, hi], [-7, -3, -2, 2, 3, 7])
        Unsigned => ([0, 1, 2, pow2 (pred w.bits), hi - 1, hi], [3, 7])
  in nub (edges ++ small ++ [bits - 1, bits, bits + 1])

------------------------------------------------------------------------------
-- The tables
------------------------------------------------------------------------------

||| A pair of operands outside a builtin's guard, and the causes its crash
||| may name.
record Stopped where
  constructor MkStopped
  lhs : Integer
  rhs : Integer
  causes : List1 Cause

||| The cases of a test, grouped by what they apply, each row its operands
||| and the value the builtin must give: a builtin of two values of a type,
||| whose value is of `result` (the type itself, or Int for a comparison),
||| with the pairs its guard stops; or a cast of a type to another, of one
||| value. A row holds exactly the operands its group's builtin takes, so
||| no program can be written with one too few or too many.
data Segment : Type where
  OnTwo : (b : Builtin) -> (operands : FixedTy) -> (result : FixedTy) ->
          List (Integer, Integer, Integer) -> List Stopped -> Segment
  CastTo : (b : Builtin) -> (from : FixedTy) -> (to : FixedTy) -> List (Integer, Integer) -> Segment

||| How many cases a group runs to its end.
rowCount : Segment -> Nat
rowCount (OnTwo _ _ _ rows _) = length rows
rowCount (CastTo _ _ _ rows) = length rows

||| The pairs a group's guard stops.
stopsOf : Segment -> List Stopped
stopsOf (OnTwo _ _ _ _ stops) = stops
stopsOf (CastTo _ _ _ _) = []

||| The builtin of two values of `f`, to a value of a fixed width, that `b`
||| is, if it is one.
twoOf : FixedTy -> Builtin -> Maybe FixedTy
twoOf f b = case (b.takes, b.gives) of
  ([TIntegral (Sized a), TIntegral (Sized c)], TIntegral (Sized r)) => if a == f && c == f then Just r else Nothing
  _ => Nothing

||| The cast of a value of `f` to another fixed width that `b` is, if it is
||| one.
castOf : FixedTy -> Builtin -> Maybe FixedTy
castOf f b = case (b.takes, b.gives) of
  ([TIntegral (Sized a)], TIntegral (Sized u)) => if a == f && u /= f then Just u else Nothing
  _ => Nothing

||| A builtin of two values of `f` on every pair of its operands.
twoSegment : FixedTy -> FixedTy -> Builtin -> Segment
twoSegment f r b =
  let answered = [ (a, c, answer b [a, c]) | a <- operands f, c <- operands f ]
  in OnTwo b f r (mapMaybe given answered) (mapMaybe stopped answered)
  where
    given : (Integer, Integer, Maybe Answer) -> Maybe (Integer, Integer, Integer)
    given (a, c, Just (Gives v)) = Just (a, c, v)
    given _ = Nothing
    stopped : (Integer, Integer, Maybe Answer) -> Maybe Stopped
    stopped (a, c, Just (CrashesBy why)) = Just (MkStopped a c why)
    stopped _ = Nothing

||| A cast of `f` to `u` on every operand of `f`.
castSegment : FixedTy -> FixedTy -> Builtin -> Segment
castSegment f u b = CastTo b f u (mapMaybe (\a => given a (answer b [a])) (operands f))
  where
    given : Integer -> Maybe Answer -> Maybe (Integer, Integer)
    given a (Just (Gives v)) = Just (a, v)
    given _ _ = Nothing

||| A test's name: its type in lower case, and its builtin's word.
testName : FixedTy -> Builtin -> String
testName f b = "prim-" ++ toLower (tyName (fixedTy f)) ++ "-" ++ b.spelling.stem

||| Every test: its name, and the groups of cases its programs check; a
||| test whose builtins the oracle computes nothing of is none.
tests : List (String, List Segment)
tests = do
  f <- fixedTys
  let twos = mapMaybe (\b => (\r => (testName f b, [twoSegment f r b])) <$> twoOf f b) builtins
      castBuiltins = mapMaybe (\b => (\u => (b, u)) <$> castOf f b) builtins
      casts = case castBuiltins of
        [] => []
        ((b, _) :: _) => [(testName f b, map (\(c, u) => castSegment f u c) castBuiltins)]
  filter (\(_, ss) => any (\s => rowCount s + length (stopsOf s) > 0) ss) (twos ++ casts)

||| The tests by name.
byName : SortedMap String (List Segment)
byName = fromList tests

||| What `result` is when every case agrees: no case is numbered 0, so it
||| cannot be mistaken for the number of one that disagrees.
agreed : Nat
agreed = 0

||| A value of the width of Int, as a program writes it.
intText : Integer -> String
intText v =
  let asInt = wrap (width FInt) v
  in if asInt >= 0 then show asInt else "(" ++ show asInt ++ ")"

||| A value of Int, as an Int of a fixed-width type: Int itself, or the
||| one cast from Int. A written operand and one read from standard input
||| take this one way into their type, so both programs convert alike.
fromInt : FixedTy -> String -> String
fromInt f v = if f == FInt then v else "(" ++ castNamed Prims.tInt (fixedTy f) ++ " " ++ v ++ ")"

||| The comparison a case's value is held to its expected one with.
eqName : FixedTy -> String
eqName f = spellingText (MkSpelling "eq" [fixedTy f])

------------------------------------------------------------------------------
-- Operands written in the program
------------------------------------------------------------------------------

||| An Idris expression of type t with value v: an Int literal, cast to t.
||| A builtin applied to literals reaches this compiler as written
||| (upstream/18-elaboration-primitive-folding), so every case is this
||| compiler's arithmetic.
lit : FixedTy -> Integer -> String
lit f v = fromInt f (intText v)

||| A case written out: the expression, the type of its result and the
||| value it must have.
record CaseText where
  constructor MkCaseText
  expression : String
  resultTy : FixedTy
  expected : Integer

||| The cases of a group, written out, in its order.
written : Segment -> List CaseText
written (OnTwo b f r rows _) =
  [ MkCaseText ("(" ++ spellingText b.spelling ++ " " ++ lit f a ++ " " ++ lit f c ++ ")") r e | (a, c, e) <- rows ]
written (CastTo b f u rows) =
  [ MkCaseText ("(" ++ spellingText b.spelling ++ " " ++ lit f a ++ ")") u e | (a, e) <- rows ]

||| The Prog module that checks the cases with their operands written in.
writtenProgram : List Segment -> String
writtenProgram segments =
  let cases = concatMap written segments
      numbered = zip [1 .. length cases] cases
      body = foldr (\(i, w), rest =>
                      "chk (" ++ eqName w.resultTy ++ " " ++ w.expression ++ " " ++ lit w.resultTy w.expected ++ ") "
                        ++ show i ++ "\n  (" ++ rest ++ ")")
                   (show agreed) numbered
  in unlines
       [ "module Prog", ""
       , "-- Generated by harness/Sem.idr.", ""
       , "public export"
       , "chk : Int -> Int -> Int -> Int"
       , "chk 1 _ rest = rest"
       , "chk _ i _ = i", ""
       , "public export partial"
       , "result : Int"
       , "result ="
       , "  " ++ body
       ]

------------------------------------------------------------------------------
-- Operands read from standard input
------------------------------------------------------------------------------

||| Each group with the number of its first case: the groups' cases are
||| numbered as the written program numbers them, one after another.
numberedFrom : Nat -> List Segment -> List (Nat, Segment)
numberedFrom _ [] = []
numberedFrom first (s :: ss) = (first, s) :: numberedFrom (first + rowCount s) ss

||| The function of group `k`, which checks the rows of its line: each row
||| the case's number, its operands and the value it must give, every one
||| an Int, converted into the group's types as a written operand is. It is
||| given how many rows its line holds, so a line of another length, or a
||| row cut short, names the group's first case instead of passing. Its
||| lines, and the column at which its builtin's application starts in the
||| fourth, its row's clause: the site a crash of the builtin names.
reader : Nat -> (Nat, Segment) -> (List String, Nat)
reader k (first, segment) =
  let name = "seg" ++ show k
      (row, before, applied, after) = the (String, String, String, String) $ case segment of
        OnTwo b f r _ _ =>
          ( "(i :: a :: b :: e :: more)", eqName r ++ " (", spellingText b.spelling
          , " " ++ fromInt f "a" ++ " " ++ fromInt f "b" ++ ") " ++ fromInt r "e" )
        CastTo b f u _ =>
          ( "(i :: a :: e :: more)", eqName u ++ " (", spellingText b.spelling
          , " " ++ fromInt f "a" ++ ") " ++ fromInt u "e" )
      clause = name ++ " (S k) " ++ row ++ " rest = chk (" ++ before
  in ( [ "partial"
       , name ++ " : Nat -> List Int -> Int -> Int"
       , name ++ " Z [] rest = rest"
       , clause ++ applied ++ after ++ ") i (" ++ name ++ " k more rest)"
       , name ++ " _ _ _ = " ++ show first
       , "" ]
     , S (length clause) )

||| The lines of the stdin program before its groups' readers.
stdinHeader : List String
stdinHeader =
  [ "module Prog", ""
  , "-- Generated by harness/Sem.idr: every operand, and the value each case"
  , "-- must give, is read from standard input, so no case is known before"
  , "-- the program runs.", ""
  , "import Data.String", ""
  , "public export"
  , "chk : Int -> Int -> Int -> Int"
  , "chk 1 _ rest = rest"
  , "chk _ i _ = i", ""
  , "ints : String -> List Int"
  , "ints text = map cast (words text)", "" ]

||| The place of a group's builtin in the stdin program: its line and its
||| column, each from 1.
record Site where
  constructor MkSite
  line : Nat
  column : Nat

||| The Prog module that checks the cases with every operand read from
||| standard input, a line per group, and the site of each group's builtin.
stdinProgram : List Segment -> (String, List Site)
stdinProgram segments =
  let groups = zip [1 .. length segments] (numberedFrom 1 segments)
      readers = map (\(k, g) => (k, reader k g)) groups
      sites = map (\(k, (_, column)) => MkSite (length stdinHeader + 6 * pred k + 4) column) readers
      text = unlines $
        stdinHeader
        ++ (readers >>= \(_, (ls, _)) => ls)
        ++ [ "public export partial"
           , "result : IO Int"
           , "result = do" ]
        ++ map (\(k, _) => "  " ++ lineName k ++ " <- getLine") groups
        ++ [ "  pure (" ++ foldr call (show agreed) groups ++ ")" ]
  in (text, sites)
  where
    lineName : Nat -> String
    lineName k = "line" ++ show k
    call : (Nat, (Nat, Segment)) -> String -> String
    call (k, (_, s)) rest =
      "seg" ++ show k ++ " " ++ show (rowCount s) ++ " (ints " ++ lineName k ++ ") (" ++ rest ++ ")"

||| A value as the stdin program reads it: an Int, in decimal.
intWord : Integer -> String
intWord v = show (wrap (width FInt) v)

||| A stopped pair put in place of a group's first row: the group's
||| number, and the pair.
record InPlace where
  constructor MkInPlace
  group : Nat
  pair : Stopped

||| The input of the stdin program: a line per group, each row its case's
||| number, its operands and the value it must give, every one as an Int;
||| with a stopped pair in place, that group's first row holds its operands.
stdinText : List Segment -> Maybe InPlace -> String
stdinText segments stop = unlines (map rowsOf (zip [1 .. length segments] (numberedFrom 1 segments)))
  where
    placed : Nat -> List (Integer, Integer, Integer) -> List (Integer, Integer, Integer)
    placed k rows = case (stop, rows) of
      (Just (MkInPlace g p), (_, _, e) :: rest) => if g == k then (p.lhs, p.rhs, e) :: rest else rows
      _ => rows
    rowsOf : (Nat, (Nat, Segment)) -> String
    rowsOf (k, (first, OnTwo _ _ _ rows _)) =
      unwords (concat (zipWith (\i, (a, b, e) => [show i, intWord a, intWord b, intWord e])
                               [first .. first + length rows] (placed k rows)))
    rowsOf (_, (first, CastTo _ _ _ rows)) =
      unwords (concat (zipWith (\i, (a, e) => [show i, intWord a, intWord e])
                               [first .. first + length rows] rows))

||| The program an end-to-end fixture builds, and the file Prog is in: the
||| runtime's line for a crash names both.
programName : String
programName = "prog"

progFile : String
progFile = "Prog.idr"

||| A case of the stdin program: its directory's name and its files.
StdinCase : Type
StdinCase = (String, List (String, String))

||| The cases of the stdin program: one of every pair inside its guard,
||| which prints the value `result` ends with when every case agrees; and
||| one of each pair a guard stops, its input every other case's and its
||| group's first row its pair, which ends by its guard's crash: the status
||| and the runtime's line of its first cause, the only one of a builtin of
||| one guard. A group with no row has no first row to hold a stopped pair.
stdinCases : List Segment -> List StdinCase
stdinCases segments =
  let (_, sites) = stdinProgram segments
      inside = ("operands", [("stdin", stdinText segments Nothing), ("expected-stdout", show agreed ++ "\n")])
      stoppedCases = do
        (k, (segment, site)) <- zip [1 .. length segments] (zip segments sites)
        if rowCount segment == 0 then [] else do
          (j, p) <- zip [1 .. length (stopsOf segment)] (stopsOf segment)
          let cause = head p.causes
          pure ( "crash-" ++ show k ++ "-" ++ show j
               , [ ("stdin", stdinText segments (Just (MkInPlace k p)))
                 , ("expected-ending", crashedText cause ++ "\n")
                 , ("expected-stderr", programName ++ ": fatal: " ++ progFile ++ ":" ++ show site.line ++ ":"
                                       ++ show site.column ++ ": " ++ causePhraseOf cause ++ "\n") ] )
  in inside :: stoppedCases

------------------------------------------------------------------------------
-- What the runner asks
------------------------------------------------------------------------------

||| How a test's program meets its operands: written in it, so this
||| compiler computes every case while it compiles; or read from standard
||| input, so only the compiled program's own arithmetic can.
public export
data Given = InProgram | OnStdin

||| The word `runtests --sem-program` takes for each.
export
givenOf : String -> Maybe Given
givenOf "written" = Just InProgram
givenOf "stdin" = Just OnStdin
givenOf _ = Nothing

||| The name of every test, in the order of the tables: the runner runs
||| tests/semantics once for each (harness/Main.idr).
export
names : List String
names = map fst tests

||| A test's program, by its name, as its operands are given to it.
export
programOf : Given -> (name : String) -> Maybe String
programOf InProgram name = writtenProgram <$> lookup name byName
programOf OnStdin name = fst . stdinProgram <$> lookup name byName

||| The stdout of a test's written program, by its name: Main.idr prints
||| `result` with printLn, and every case agrees.
export
expectedOf : (name : String) -> Maybe String
expectedOf name = (\_ => show agreed ++ "\n") <$> lookup name byName

||| `runtests --sem-cases <name> <dir>`: the cases of a test's stdin
||| program written under `dir`, a directory each, as an end-to-end
||| fixture's cases are.
export
writeCases : (name : String) -> (dir : String) -> IO (Either String ())
writeCases name dir = case lookup name byName of
  Nothing => pure (Left ("no semantics test " ++ name))
  Just segments => go (stdinCases segments)
  where
    files : String -> List (String, String) -> IO (Either String ())
    files _ [] = pure (Right ())
    files at ((file, text) :: rest) = do
      Right () <- writeFile (at ++ "/" ++ file) text
        | Left err => pure (Left (at ++ "/" ++ file ++ ": " ++ show err))
      files at rest
    go : List StdinCase -> IO (Either String ())
    go [] = pure (Right ())
    go ((caseName, contents) :: rest) = do
      let at = dir ++ "/" ++ caseName
      Right () <- createDir at
        | Left err => pure (Left (at ++ ": " ++ show err))
      Right () <- files at contents
        | Left why => pure (Left why)
      go rest
