-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The linear generator: straight-line programs over mlir-linear's linear
||| lists, each written twice, over `LList` with `-@` and `!*`, and as its
||| twin over `List` with `->` and no bang; and the in-place promise's
||| verdict on each, predicted here from its own statement of the rule
||| (tests/linear-twin):
|||
|||     runtests --linear-program <seed> <case> linear|twin|stdin|verdict
|||     runtests --linear-program checks
|||     runtests --linear-check <seed> <case> <exit-status> <report>
|||
||| Linearity is a property of speed, never of meaning, so every program
||| the compiler accepts prints and ends as its twin does. A function that
||| takes its list apart and builds a list from its cells (`bump`,
||| `doubled`, the library's `reverse`) is held to the promise that its
||| argument is exclusive at every call, and a call whose argument is not
||| is refused, `unsupported (uniqueness)` at its line. The compiler must
||| refuse exactly the lines predicted here.
|||
||| A use of a value counts against a rebuild only if it may still hold the
||| value there. The program's reads (`sumW`, `lenW`) are unrestricted
||| functions that only read the list they are lent and keep nothing of
||| it, so a read ends when it returns: one before the rebuild never counts,
||| printed or unused, and one after it always does. A rebuild keeps the
||| cells of what it takes apart, so it is no borrow, and an earlier rebuild
||| of the same value counts as a later use does. A name bound to a name is
||| the value again, and holds nothing of its own. The argument of a
||| rebuild is exclusive, then, when no later use of its value is evaluated
||| under any name, nor any earlier rebuild of it, and it was exclusive
||| where it was made: built fresh, or given by a rebuild of an exclusive
||| value.
|||
||| What the generator keeps out is the harness's own error, never the
||| compiler's: a program names only lists it bound. Sharing a list is a
||| draw like any other, so programs the promise refuses are as easy to
||| make as programs it accepts.
|||
||| A program is drawn on its own seed (output n of splitmix64 from the
||| run's seed), as Fuzz's cases are, so a seed and a case replay it.
module Linear

import Prelude
import Data.DPair
import Data.Fin
import Data.List
import Data.List1
import Data.Maybe
import Data.Nat
import Data.String
import Data.Vect
import Gen
import Facts
import Files
import Reject

import IdrisMLIR.Spec.Core.Rules
import IdrisMLIR.Spec.Core.Verdict

%default total

------------------------------------------------------------------------------
-- A program
------------------------------------------------------------------------------

||| A function of the program that takes its list apart and builds a list
||| from its cells: the in-place promise binds each of its calls.
data Rebuilder = Bump | Doubled | Reverse

||| A read of the program: an unrestricted function that walks the list it
||| is lent and keeps nothing of it.
data Reader = Sum | Length

||| A list expression of a program whose statements so far bound `n`
||| names, the latest first: a list built fresh, `extra` longer than the
||| program's input says; one of those names, never another; or a rebuild
||| of a list.
data LExpr : (n : Nat) -> Type where
  Build : (extra : Nat) -> LExpr n
  Name : Fin n -> LExpr n
  Rebuild : Rebuilder -> LExpr n -> LExpr n

||| main's statements, from `n` names bound: done; a list bound to the next
||| name, which the rest may name; a read of a list, printed; or a read
||| whose result nothing uses, which is evaluated all the same.
data Stmts : (n : Nat) -> Type where
  Done : Stmts n
  Bind : LExpr n -> Stmts (S n) -> Stmts n
  Print : Reader -> LExpr n -> Stmts n -> Stmts n
  Unused : Reader -> LExpr n -> Stmts n -> Stmts n

||| A program: the number its input line holds, which every fresh list's
||| length starts from, so no list is known before the program runs; and
||| main's statements.
record Program where
  constructor MkProgram
  input : Nat
  statements : Stmts 0

------------------------------------------------------------------------------
-- Drawing a program
------------------------------------------------------------------------------

||| What a program's draws are weighted by, one distribution per choice:
||| a statement (a list bound, a read printed, a read unused), a leaf (a
||| list built fresh, a name), an expression's shape (a leaf, a rebuild),
||| the rebuilder and the reader. Each run draws its own by swarm testing,
||| so one program names its lists again and again and another never does.
record Mix where
  constructor MkMix
  statement : Weights 3
  leaf : Weights 2
  shape : Weights 2
  rebuilder : Weights 3
  reader : Weights 2

||| The weights a run's are drawn from: names drawn more often than fresh
||| lists, so a program shares what it bound.
baseMix : Mix
baseMix = MkMix (MkWeights [3, 2, 1]) (MkWeights [1, 3]) (MkWeights [2, 1]) (MkWeights [2, 1, 1]) (MkWeights [2, 1])

genMix : Gen Mix
genMix = [| MkMix (swarm baseMix.statement) (swarm baseMix.leaf) (swarm baseMix.shape)
                  (swarm baseMix.rebuilder) (swarm baseMix.reader) |]

||| An option, as likely as its weight.
choose : Weights n -> Gen (Fin n)
choose w = map (\picked => picked.fst) (weighted w)

rebuilderOf : Fin 3 -> Rebuilder
rebuilderOf FZ = Bump
rebuilderOf (FS FZ) = Doubled
rebuilderOf (FS (FS _)) = Reverse

readerOf : Fin 2 -> Reader
readerOf FZ = Sum
readerOf (FS _) = Length

||| A leaf. With no name bound, a fresh list is the only leaf there is, so
||| the draw is that move, whatever the weights.
genLeaf : (n : Nat) -> Mix -> Gen (LExpr n)
genLeaf Z _ = map (Build . finToNat) (draw 4)
genLeaf (S k) mix = do
  c <- choose mix.leaf
  case c of
    FZ => map (Build . finToNat) (draw 4)
    FS _ => map Name (draw (S k))

||| An expression of at most `depth` rebuilds.
genExpr : (depth : Nat) -> (n : Nat) -> Mix -> Gen (LExpr n)
genExpr Z n mix = genLeaf n mix
genExpr (S d) n mix = do
  c <- choose mix.shape
  case c of
    FZ => genLeaf n mix
    FS _ => [| Rebuild (map rebuilderOf (choose mix.rebuilder)) (genExpr d n mix) |]

genStmts : (count : Nat) -> (n : Nat) -> Mix -> Gen (Stmts n)
genStmts Z _ _ = pure Done
genStmts (S c) n mix = do
  kind <- choose mix.statement
  case kind of
    FZ => [| Bind (genExpr 2 n mix) (genStmts c (S n) mix) |]
    FS FZ => [| Print (map readerOf (choose mix.reader)) (genExpr 2 n mix) (genStmts c n mix) |]
    FS (FS _) => [| Unused (map readerOf (choose mix.reader)) (genExpr 2 n mix) (genStmts c n mix) |]

||| A program of three to eight statements.
genProgram : Gen Program
genProgram = do
  mix <- genMix
  k <- map finToNat (draw 7)
  count <- map (\i => 3 + finToNat i) (draw 6)
  map (MkProgram k) (genStmts count 0 mix)

||| The draws a program makes, with room to spare: the mix's, the input,
||| the count, and at most nine for each statement.
capacity : Nat
capacity = 128

||| The program of case `i` of `seed`.
programAt : Bits64 -> Nat -> Program
programAt seed i = (seeded capacity (caseSeed seed i) genProgram).value

------------------------------------------------------------------------------
-- Writing a program
------------------------------------------------------------------------------

||| Which of the two programs is written: over linear lists, or its twin.
data Form = OverLinear | OverPlain

||| The lines before main's statements: a header naming what wrote the
||| program, the functions it calls, and main's first lines, which read
||| the input. The reads are total, so an unused one may be deleted, which
||| changes neither the verdict nor what the program prints.
prefixLines : Form -> (request : String) -> List String
prefixLines OverLinear request =
  [ "module Main", ""
  , "-- Generated by harness/Linear.idr: runtests --linear-program " ++ request, ""
  , "import Prelude"
  , "import Linear.Notation"
  , "import Linear.List", ""
  , "build : Int -> LList (!* Int) -@ LList (!* Int)"
  , "build n acc = if n <= 0 then acc else build (n - 1) (MkBang n :: acc)", ""
  , "bump : LList (!* Int) -@ LList (!* Int)"
  , "bump [] = []"
  , "bump (MkBang x :: xs) = MkBang (x + 1) :: bump xs", ""
  , "doubled : LList (!* Int) -@ LList (!* Int)"
  , "doubled [] = []"
  , "doubled (MkBang x :: xs) = MkBang (x * 2) :: doubled xs", ""
  , "total"
  , "sumW : LList (!* Int) -> Int"
  , "sumW [] = 0"
  , "sumW (MkBang x :: xs) = x + 31 * sumW xs", ""
  , "total"
  , "lenW : LList (!* Int) -> Nat"
  , "lenW [] = Z"
  , "lenW (_ :: xs) = S (lenW xs)", ""
  , "main : IO ()"
  , "main = do"
  , "  text <- getLine"
  , "  let k : Int = cast text" ]
prefixLines OverPlain request =
  [ "module Main", ""
  , "-- Generated by harness/Linear.idr: runtests --linear-program " ++ request, ""
  , "import Prelude", ""
  , "build : Int -> List Int -> List Int"
  , "build n acc = if n <= 0 then acc else build (n - 1) (n :: acc)", ""
  , "bump : List Int -> List Int"
  , "bump [] = []"
  , "bump (x :: xs) = (x + 1) :: bump xs", ""
  , "doubled : List Int -> List Int"
  , "doubled [] = []"
  , "doubled (x :: xs) = (x * 2) :: doubled xs", ""
  , "reverseOnto : List Int -> List Int -> List Int"
  , "reverseOnto acc [] = acc"
  , "reverseOnto acc (x :: xs) = reverseOnto (x :: acc) xs", ""
  , "total"
  , "sumW : List Int -> Int"
  , "sumW [] = 0"
  , "sumW (x :: xs) = x + 31 * sumW xs", ""
  , "total"
  , "lenW : List Int -> Nat"
  , "lenW [] = Z"
  , "lenW (_ :: xs) = S (lenW xs)", ""
  , "main : IO ()"
  , "main = do"
  , "  text <- getLine"
  , "  let k : Int = cast text" ]

||| The line of the linear program its first statement is on, counting
||| from 1: each statement is on a line of its own after it, so the
||| prediction names a call by its line, as the compiler reports it.
firstLine : Nat
firstLine = S (length (prefixLines OverLinear ""))

||| The name a name of the `n` bound writes: names are numbered as they are
||| bound, and a name holds the latest first.
nameText : (n : Nat) -> Fin n -> String
nameText n i = "v" ++ show (minus n (S (finToNat i)))

rebuilderText : Form -> Rebuilder -> String
rebuilderText _ Bump = "bump"
rebuilderText _ Doubled = "doubled"
rebuilderText OverLinear Reverse = "Linear.List.reverse"
rebuilderText OverPlain Reverse = "reverseOnto []"

exprText : Form -> (n : Nat) -> LExpr n -> String
exprText _ _ (Build extra) = "build (k + " ++ show extra ++ ") []"
exprText _ n (Name i) = nameText n i
exprText form n (Rebuild r e) = rebuilderText form r ++ " (" ++ exprText form n e ++ ")"

readerText : Reader -> String
readerText Sum = "sumW"
readerText Length = "lenW"

||| main's statements from statement `j`, a line each; an unused read is
||| bound to a name of its statement, which nothing names.
stmtLines : Form -> (j : Nat) -> (n : Nat) -> Stmts n -> List String
stmtLines _ _ _ Done = []
stmtLines form j n (Bind e rest) =
  ("  let v" ++ show n ++ " = " ++ exprText form n e) :: stmtLines form (S j) (S n) rest
stmtLines form j n (Print r e rest) =
  ("  printLn (" ++ readerText r ++ " (" ++ exprText form n e ++ "))") :: stmtLines form (S j) n rest
stmtLines form j n (Unused r e rest) =
  ("  let unused" ++ show j ++ " = " ++ readerText r ++ " (" ++ exprText form n e ++ ")") :: stmtLines form (S j) n rest

||| A program written in one form; a do block ends in an action, so main
||| ends in `pure ()` after its statements.
programText : Form -> (request : String) -> Program -> String
programText form request p = unlines (prefixLines form request ++ stmtLines form 1 0 p.statements ++ ["  pure ()"])

------------------------------------------------------------------------------
-- The promise, as the harness states it
------------------------------------------------------------------------------

||| How a use holds the value it uses: a read lends it and keeps nothing
||| once it returns; a rebuild keeps its cells.
data Holds = Lends | Keeps

||| A use of a value: the line of its statement, and how it holds it.
record Use where
  constructor MkUse
  line : Nat
  holds : Holds

||| Whether a use may still hold a value at a rebuild of it on `line`:
||| every use evaluated after the rebuild does, and a use before it does
||| when it kept the value. A statement has one leaf, so the rebuild's own
||| use is the only one on its line.
holdsAt : (line : Nat) -> Use -> Bool
holdsAt line u = case u.holds of
  Lends => u.line > line
  Keeps => u.line /= line

||| Where a value of the program, after the `k` before it, the latest
||| first, was made: built fresh, or given by a rebuild, on a line, of one
||| of those before it.
data Origin : Nat -> Type where
  Fresh : Origin k
  RebuiltFrom : (line : Nat) -> Fin k -> Origin k

||| A value the program makes: the uses of it the program evaluates, and
||| where it was made. A name bound to a name is that value again, never a
||| new one.
record Value (k : Nat) where
  constructor MkValue
  uses : List Use
  origin : Origin k

||| The program's values, the latest first: each names only those before
||| it, so no value is made from itself.
data Values : Nat -> Type where
  NoValue : Values 0
  Also : Value k -> Values k -> Values (S k)

||| One more use of a value.
useOf : Fin k -> Use -> Values k -> Values k
useOf FZ u (Also v vs) = Also ({ uses $= (u ::) } v) vs
useOf (FS p) u (Also v vs) = Also v (useOf p u vs)

||| The uses of a value.
usesOf : Fin k -> Values k -> List Use
usesOf FZ (Also v _) = v.uses
usesOf (FS p) (Also _ vs) = usesOf p vs

||| Whether each value was exclusive where it was made, the latest first:
||| built fresh, or rebuilt from a value exclusive at that rebuild.
madeExclusive : Values k -> Vect k Bool
madeExclusive NoValue = []
madeExclusive (Also v vs) =
  let before = madeExclusive vs in
  (case v.origin of
     Fresh => True
     RebuiltFrom line p => index p before && not (any (holdsAt line) (usesOf p vs))) :: before

||| What an expression reads: the list it starts from, fresh or a name's
||| value; and whether a rebuild takes it.
data Leaf : Nat -> Type where
  FreshLeaf : Leaf n
  Named : Fin n -> Leaf n

data Taken = Untaken | Rebuilt

record Spine (n : Nat) where
  constructor MkSpine
  taken : Taken
  leaf : Leaf n

||| An expression has one path, every rebuild on it: its leaf, and whether
||| a rebuild takes what the leaf gives.
spineOf : LExpr n -> Spine n
spineOf (Build _) = MkSpine Untaken FreshLeaf
spineOf (Name i) = MkSpine Untaken (Named i)
spineOf (Rebuild _ e) = MkSpine Rebuilt (spineOf e).leaf

||| A rebuild of a name's value: its line, and the value.
Pending : Nat -> Type
Pending k = (Nat, Fin k)

||| What a statement does to the values: the use its leaf makes, a read's
||| or a rebuild's, the rebuild owed its check, and where the list it
||| gives was made.
record Step (k : Nat) where
  constructor MkStep
  values : Values k
  pending : List (Pending k)
  origin : Origin k

stepOf : (line : Nat) -> Vect n (Fin k) -> Values k -> List (Pending k) -> Spine n -> Step k
stepOf _ _ values pending (MkSpine _ FreshLeaf) = MkStep values pending Fresh
stepOf line names values pending (MkSpine Untaken (Named i)) =
  let v = index i names in MkStep (useOf v (MkUse line Lends) values) pending Fresh
stepOf line names values pending (MkSpine Rebuilt (Named i)) =
  let v = index i names in
  MkStep (useOf v (MkUse line Keeps) values) ((line, v) :: pending) (RebuiltFrom line v)

||| The lines whose calls the promise refuses, in order: every statement's
||| uses recorded first, since a use after a rebuild shares its argument,
||| then each rebuild of a value whose argument is not exclusive there. The
||| names in scope are each a value; a name bound to a name is its value
||| again, and makes no use of it. A read's step leaves its origin unread.
refusedLines : (line : Nat) -> Vect n (Fin k) -> Values k -> List (Pending k) -> Stmts n -> List Nat
refusedLines _ _ values pending Done =
  let made = madeExclusive values in
  reverse (mapMaybe (\(l, v) => if index v made && not (any (holdsAt l) (usesOf v values)) then Nothing else Just l) pending)
refusedLines line names values pending (Bind (Name i) rest) =
  refusedLines (S line) (index i names :: names) values pending rest
refusedLines line names values pending (Bind e rest) =
  let s = stepOf line names values pending (spineOf e) in
  refusedLines (S line) (FZ :: map FS names) (Also (MkValue [] s.origin) s.values)
               (map (\(l, v) => (l, FS v)) s.pending) rest
refusedLines line names values pending (Print _ e rest) =
  let s = stepOf line names values pending (spineOf e) in
  refusedLines (S line) names s.values s.pending rest
refusedLines line names values pending (Unused _ e rest) =
  let s = stepOf line names values pending (spineOf e) in
  refusedLines (S line) names s.values s.pending rest

||| The verdict the promise gives a program: accepted, or refused at each
||| of its lines, which are some.
data Verdict = Accepted | Refused (List1 Nat)

predict : Program -> Verdict
predict p = case refusedLines firstLine [] NoValue [] p.statements of
  [] => Accepted
  (l :: ls) => Refused (l ::: ls)

verdictText : Verdict -> String
verdictText Accepted = "accepted"
verdictText (Refused ls) = "refused at " ++ joinBy ", " (map (\l => "line " ++ show l) (forget ls))

------------------------------------------------------------------------------
-- Holding a compilation to the prediction
------------------------------------------------------------------------------

||| Whether a refusal is by the promise's rule.
byUniqueness : Refusal -> Bool
byUniqueness r = maybe False (\got => phraseOf got == phraseOf uniqueness) r.rule

||| What disagrees between the prediction and a compilation of the linear
||| program: its exit status, and its report, read once (Reject.idr). An
||| accepted program compiles with no error; a refused one is refused by
||| the promise alone, at exactly the lines predicted, each at least once.
disagreements : Verdict -> (status : Nat) -> Report -> List String
disagreements Accepted status report =
  (if status == 0 then [] else ["predicted accepted, but the compilation exited " ++ show status])
  ++ (if null report.errors then [] else ["predicted accepted, but the report holds " ++ show (length report.errors) ++ " errors"])
disagreements (Refused ls) status report =
  let wanted = forget ls
      reported = nub (sort (mapMaybe (\r => map (.line) r.place) report.errors))
  in (if status == 0 then ["predicted " ++ verdictText (Refused ls) ++ ", but the compilation exited 0"] else [])
     ++ (case report.verdict of
           Just VerdictInternal => ["predicted a refusal, but the compiler ended in an internal error"]
           _ => [])
     ++ (if all byUniqueness report.errors && not (null report.errors) then []
         else ["predicted refusals by uniqueness alone, but the report's errors are by other rules or none"])
     ++ (if reported == wanted then []
         else ["predicted " ++ verdictText (Refused ls) ++ ", but the report names "
               ++ (if null reported then "no line" else joinBy ", " (map (\l => "line " ++ show l) reported))])

------------------------------------------------------------------------------
-- The predictor's own checks
------------------------------------------------------------------------------

||| The line of main's statement `j`, counting from 1.
statementLine : Nat -> Nat
statementLine j = firstLine + minus j 1

||| A list built fresh and named `v0`, then the rest.
withList : Stmts 1 -> Stmts 0
withList = Bind (Build 0)

isAccepted : Verdict -> Bool
isAccepted Accepted = True
isAccepted (Refused _) = False

refusedAt : List Nat -> Verdict -> Bool
refusedAt _ Accepted = False
refusedAt wanted (Refused ls) = forget ls == wanted

verdictOf : Stmts 1 -> Verdict
verdictOf rest = predict (MkProgram 3 (withList rest))

||| The predictor on programs whose verdicts the rule fixes, and the
||| generator's spread over the cases of one seed: each a name and
||| whether it holds, on whichever host runs it.
export
checks : List (String, Bool)
checks =
  [ ("a list read after it is rebuilt is refused at the rebuild",
     refusedAt [statementLine 2] (verdictOf (Print Sum (Rebuild Bump (Name FZ)) (Print Sum (Name FZ) Done))))
  , ("a list read, unused, after it is rebuilt is refused at the rebuild",
     refusedAt [statementLine 2] (verdictOf (Print Sum (Rebuild Bump (Name FZ)) (Unused Length (Name FZ) Done))))
  , ("a list read before it is rebuilt is accepted",
     isAccepted (verdictOf (Print Length (Name FZ) (Print Sum (Rebuild Reverse (Name FZ)) Done))))
  , ("a list read, unused, before it is rebuilt is accepted",
     isAccepted (verdictOf (Unused Length (Name FZ) (Print Sum (Rebuild Bump (Name FZ)) Done))))
  , ("a list rebuilt once is accepted",
     isAccepted (verdictOf (Print Sum (Rebuild Doubled (Name FZ)) Done)))
  , ("a list read twice and rebuilt nowhere is accepted",
     isAccepted (verdictOf (Print Sum (Name FZ) (Print Length (Name FZ) Done))))
  , ("a list rebuilt twice is refused at both rebuilds",
     refusedAt [statementLine 2, statementLine 3]
       (verdictOf (Print Sum (Rebuild Bump (Name FZ)) (Print Sum (Rebuild Doubled (Name FZ)) Done))))
  , ("a name for a list, rebuilt once, is accepted",
     isAccepted (verdictOf (Bind (Name FZ) (Print Sum (Rebuild Bump (Name FZ)) Done))))
  , ("a name for a list, rebuilt after the list is read, is accepted",
     isAccepted (verdictOf (Bind (Name FZ) (Print Sum (Name (FS FZ)) (Print Sum (Rebuild Bump (Name FZ)) Done)))))
  , ("a name for a list, rebuilt before the list is read, is refused at the rebuild",
     refusedAt [statementLine 3]
       (verdictOf (Bind (Name FZ) (Print Sum (Rebuild Bump (Name FZ)) (Print Sum (Name (FS FZ)) Done)))))
  , ("a rebuild of what a refused rebuild gave is refused too",
     refusedAt [statementLine 2, statementLine 4]
       (verdictOf (Bind (Rebuild Bump (Name FZ)) (Print Sum (Name (FS FZ)) (Print Sum (Rebuild Bump (Name FZ)) Done)))))
  , ("a rebuild of a rebuild of a list used once is accepted",
     isAccepted (verdictOf (Bind (Rebuild Bump (Name FZ)) (Print Sum (Rebuild Doubled (Name FZ)) Done))))
  , ("seed 1's first 64 programs hold both verdicts",
     let verdicts = map (\i => isAccepted (predict (programAt 1 i))) [1 .. 64]
     in any id verdicts && any not verdicts)
  ]

------------------------------------------------------------------------------
-- What the runner asks
------------------------------------------------------------------------------

parseSeed : String -> Maybe Bits64
parseSeed s = cast {to = Bits64} <$> parseInteger {a = Integer} s

parseCase : String -> Maybe Nat
parseCase s = case parsePositive {a = Nat} s of
  Just (S k) => Just (S k)
  _ => Nothing

parseStatus : String -> Maybe Nat
parseStatus "0" = Just 0
parseStatus s = parsePositive {a = Nat} s

||| What `--linear-program` writes of a program.
data Part = LinearPart | TwinPart | StdinPart | VerdictPart

parsePart : String -> Maybe Part
parsePart "linear" = Just LinearPart
parsePart "twin" = Just TwinPart
parsePart "stdin" = Just StdinPart
parsePart "verdict" = Just VerdictPart
parsePart _ = Nothing

partText : (request : String) -> Part -> Program -> String
partText request LinearPart p = programText OverLinear request p
partText request TwinPart p = programText OverPlain request p
partText _ StdinPart p = show p.input ++ "\n"
partText _ VerdictPart p = verdictText (predict p) ++ "\n"

||| `runtests --linear-program <seed> <case> <part>`, or `checks`, the
||| predictor's own checks on the host that runs it, a line each.
export covering
programOf : List String -> Maybe String
programOf request@[seed, n, part] = do
  s <- parseSeed seed
  i <- parseCase n
  what <- parsePart part
  pure (partText (unwords request) what (programAt s i))
programOf ["checks"] =
  Just (unlines (map (\(name, holds) => "linear: " ++ name ++ ": " ++ (if holds then "ok" else "failed")) Linear.checks))
programOf _ = Nothing

||| `runtests --linear-check <seed> <case> <exit-status> <report>`: what
||| disagrees between the program's predicted verdict and its compilation,
||| a line each; nothing when they agree.
export covering
check : (seed, n, status, report : String) -> IO ()
check seed n status reportPath = do
  let Just s = parseSeed seed
    | Nothing => putStrLn ("not a seed: " ++ seed)
  let Just i = parseCase n
    | Nothing => putStrLn ("not a case: " ++ n)
  let Just exited = parseStatus status
    | Nothing => putStrLn ("not an exit status: " ++ status)
  text <- readIfThere reportPath
  putStr (unlines (disagreements (predict (programAt s i)) exited (reportOf (fromMaybe "" text))))
