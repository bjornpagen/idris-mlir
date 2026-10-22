-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Table-driven integer semantics over every integer type.
|||
||| Each generated program is the `Prog` module of an ordinary end-to-end
||| fixture, whose Main.idr prints `Prog.result`: 0 when every case agrees
||| with the table, and otherwise the number of the first case that
||| disagrees. The table is computed here, from what each primitive means,
||| not from the compiler.
|||
||| Every case runs twice, in two programs of one table. In one, its
||| operands are written in the program, so this compiler computes the case
||| while it compiles. In the other, every operand and the value each case
||| must give are read from standard input, so only the compiled program's
||| own arithmetic can answer: the expansion of each operation into code is
||| checked as well as its folder, and a slip in one that the other lacks
||| fails one program only.
|||
||| A test is one fixed-width type and one operation, its casts to every
||| other fixed width one test: `prim-<type>-<operation>`, the type in
||| lower case and the operation as Idris spells its primitives
||| (`prim-int8-add`, `prim-bits64-cast`). They run as
||| `tests/semantics@<name>`, one test of the runner per name
||| (harness/Main.idr), whose `run` asks the runner for the programs and
||| the input:
|||
|||     runtests --sem-program written|stdin prim-<type>-<operation>
|||     runtests --sem-stdin prim-<type>-<operation>
|||
||| `runtests --sem-expected <name>` prints the stdout either program must
||| print, the value `result` ends with when every case agrees, so that the
||| value is stated once, here.
module Sem

import Prelude
import Data.Bits
import Data.List
import Data.Maybe
import Data.SortedMap
import Data.String
import Prims

%default covering

||| A fixed-width type as a type.
fixedTy : FixedTy -> Ty
fixedTy f = TIntegral (Fixed f)

values : FixedTy -> List Integer
values f =
  let w = width f
      (lo, hi) = bounds f
  in if w.signed then [lo, lo + 1, -1, 0, 1, hi]
                 else [0, 1, 2, pow2 (pred w.bits), hi - 1, hi]

divValues : FixedTy -> List Integer
divValues f =
  let (lo, hi) = bounds f
  in if (width f).signed then [lo, -7, -2, -1, 0, 1, 2, 7, hi]
                         else [0, 1, 2, 7, hi - 1, hi]

||| The shift amounts of a type: within its width, at it and past it, and a
||| signed type's negative ones, which shift the other way.
shiftAmounts : Width -> List Integer
shiftAmounts t =
  let w = cast {to = Integer} t.bits
      within = [0, 1, 3, w - 1, w, w + 1]
  in if t.signed then within ++ [-1, -3] else within

pairs : List Integer -> List (Integer, Integer)
pairs vs = [(a, b) | a <- vs, b <- vs]

------------------------------------------------------------------------------
-- The tables
------------------------------------------------------------------------------

||| The cases of a test, grouped by what they apply, each row its operands
||| and the value the operation must give: an operation of a type to two of
||| its values, whose value is of `result` (the type itself, or Int for a
||| comparison); or a cast of a type to another, of one value. A row holds
||| exactly the operands its group's operation takes, so no program can be
||| written with one too few or too many.
data Segment : Type where
  OnTwo : (op : Op) -> (operands : FixedTy) -> (result : FixedTy) ->
          List (Integer, Integer, Integer) -> Segment
  CastTo : (from : FixedTy) -> (to : FixedTy) -> List (Integer, Integer) -> Segment

||| How many cases a group holds.
rowCount : Segment -> Nat
rowCount (OnTwo _ _ _ rows) = length rows
rowCount (CastTo _ _ rows) = length rows

||| The tables of one type, each the operation it checks and its groups.
tables : FixedTy -> List (Op, List Segment)
tables f =
  let w = width f
      vs = values f
      ds = filter (\(_, b) => b /= 0) (pairs (divValues f))
  in [ (op, [OnTwo op f f [(a, b, wrap w (g a b)) | (a, b) <- pairs vs]]) | (op, g) <- arithmetic ]
     ++ [ (Div, [OnTwo Div f f [(a, b, quotient w a b) | (a, b) <- ds]])
        , (Mod, [OnTwo Mod f f [(a, b, remainder w a b) | (a, b) <- ds]]) ]
     ++ [ (op, [OnTwo op f f [(a, b, bitwise w g a b) | (a, b) <- pairs vs]]) | (op, g) <- logical ]
     ++ [ (op, [OnTwo op f f [(a, s, shifted w left a s) | a <- vs, s <- shiftAmounts w]])
        | (op, left) <- shifts ]
     ++ [ (op, [OnTwo op f FInt [(a, b, if g a b then 1 else 0) | (a, b) <- pairs vs]])
        | (op, g) <- comparisons ]
     ++ [ (Convert, [CastTo f u [(a, wrap (width u) a) | a <- vs] | u <- fixedTys, u /= f]) ]

||| Every test: its name, and the groups of cases its programs check.
tests : List (String, List Segment)
tests = do
  f <- fixedTys
  (op, table) <- tables f
  pure ("prim-" ++ toLower (tyName (fixedTy f)) ++ "-" ++ spelling op, table)

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
fromInt f v = if f == FInt then v else "(" ++ castNamed int (fixedTy f) ++ " " ++ v ++ ")"

------------------------------------------------------------------------------
-- Operands written in the program
------------------------------------------------------------------------------

||| An Idris expression of type t with value v: an Int literal, cast to t.
||| A primitive applied to literals reaches this compiler as written
||| (upstream/18-elaboration-primitive-folding), so every case is this
||| compiler's arithmetic.
lit : FixedTy -> Integer -> String
lit f v = fromInt f (intText v)

||| A case written out: the expression, the type of its result and the
||| value it must have.
Case : Type
Case = (String, FixedTy, Integer)

||| The cases of a group, written out, in its order.
written : Segment -> List Case
written (OnTwo op f r rows) =
  [ ("(" ++ named op (fixedTy f) ++ " " ++ lit f a ++ " " ++ lit f b ++ ")", r, e) | (a, b, e) <- rows ]
written (CastTo f u rows) =
  [ ("(" ++ castNamed (fixedTy f) (fixedTy u) ++ " " ++ lit f a ++ ")", u, e) | (a, e) <- rows ]

||| The Prog module that checks the cases with their operands written in.
writtenProgram : List Segment -> String
writtenProgram segments =
  let cases = concatMap written segments
      numbered = zip [1 .. length cases] cases
      body = foldr (\(i, (expr, ty, expected)), rest =>
                      "chk (" ++ named Eq (fixedTy ty) ++ " " ++ expr ++ " " ++ lit ty expected ++ ") "
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
||| row cut short, names the group's first case instead of passing.
reader : Nat -> (Nat, Segment) -> List String
reader k (first, segment) =
  let name = "seg" ++ show k
      (row, check) = the (String, String) $ case segment of
        OnTwo op f r _ =>
          ( "(i :: a :: b :: e :: more)"
          , named Eq (fixedTy r) ++ " (" ++ named op (fixedTy f) ++ " " ++ fromInt f "a" ++ " "
              ++ fromInt f "b" ++ ") " ++ fromInt r "e" )
        CastTo f u _ =>
          ( "(i :: a :: e :: more)"
          , named Eq (fixedTy u) ++ " (" ++ castNamed (fixedTy f) (fixedTy u) ++ " " ++ fromInt f "a" ++ ") "
              ++ fromInt u "e" )
  in [ "partial"
     , name ++ " : Nat -> List Int -> Int -> Int"
     , name ++ " Z [] rest = rest"
     , name ++ " (S k) " ++ row ++ " rest = chk (" ++ check ++ ") i (" ++ name ++ " k more rest)"
     , name ++ " _ _ _ = " ++ show first
     , "" ]

||| The Prog module that checks the cases with every operand read from
||| standard input, a line per group.
stdinProgram : List Segment -> String
stdinProgram segments =
  let groups = zip [1 .. length segments] (numberedFrom 1 segments)
  in unlines $
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
       ++ (groups >>= \(k, g) => reader k g)
       ++ [ "public export partial"
          , "result : IO Int"
          , "result = do" ]
       ++ map (\(k, _) => "  " ++ line k ++ " <- getLine") groups
       ++ [ "  pure (" ++ foldr call (show agreed) groups ++ ")" ]
  where
    line : Nat -> String
    line k = "line" ++ show k
    call : (Nat, (Nat, Segment)) -> String -> String
    call (k, (_, s)) rest =
      "seg" ++ show k ++ " " ++ show (rowCount s) ++ " (ints " ++ line k ++ ") (" ++ rest ++ ")"

||| A value as the stdin program reads it: an Int, in decimal.
intWord : Integer -> String
intWord v = show (wrap (width FInt) v)

||| The input of the stdin program: a line per group, each row its case's
||| number, its operands and the value it must give, every one as an Int.
stdinText : List Segment -> String
stdinText segments = unlines (map rowsOf (numberedFrom 1 segments))
  where
    rowsOf : (Nat, Segment) -> String
    rowsOf (first, OnTwo _ _ _ rows) =
      unwords (concat (zipWith (\i, (a, b, e) => [show i, intWord a, intWord b, intWord e])
                               [first .. first + length rows] rows))
    rowsOf (first, CastTo _ _ rows) =
      unwords (concat (zipWith (\i, (a, e) => [show i, intWord a, intWord e])
                               [first .. first + length rows] rows))

------------------------------------------------------------------------------
-- What the runner asks
------------------------------------------------------------------------------

||| How a test's program meets its operands: written in it, so this
||| compiler computes every case while it compiles; or read from standard
||| input, so only the compiled program's own arithmetic can.
public export
data Given = Written | OnStdin

||| The word `runtests --sem-program` takes for each.
export
givenOf : String -> Maybe Given
givenOf "written" = Just Written
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
programOf Written name = writtenProgram <$> lookup name byName
programOf OnStdin name = stdinProgram <$> lookup name byName

||| The standard input of a test's stdin program, by its name.
export
stdinOf : (name : String) -> Maybe String
stdinOf name = stdinText <$> lookup name byName

||| The stdout of a test's programs, by its name: Main.idr prints `result`
||| with printLn, and every case agrees.
export
expectedOf : (name : String) -> Maybe String
expectedOf name = (\_ => show agreed ++ "\n") <$> lookup name byName
