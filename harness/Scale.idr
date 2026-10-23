-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The scale fixtures: programs of the shapes that once made a pass's work
||| grow faster than the program, each printed at a size and at twice it,
||| and the relation the two compilations must keep. A wall is a count that
||| grows superlinearly: a quadratic is about four times the work at twice
||| the size, at any size, so the relation finds it on fixtures small enough
||| to compile in a test, where a test that only asks a compilation to end in
||| time passes a quadratic for as long as its square fits the limit.
|||
|||     runtests --scale-print <fixture> <factor>
|||                         the fixture at its size times the factor (1 or 2):
|||                         a module of the dialect, or Idris source
|||     runtests --scale-check <report> <trace> <report> <trace>
|||                         the two compilations, at the size and at twice
|||                         it, held to the relation
|||
||| Every op, type, attribute and enum case is spelled from the dialect's
||| specification, so a renamed op changes what is printed here and no
||| fixture names a name of its own. What a fixture's text holds besides is
||| the program's own: its functions, values and families' labels.
|||
||| What is counted is never a time: the report's statistics (each pass's
||| counters, each solve's work, each pass's footprint) and how many times
||| each zone of the time trace ran (a pass on an op, an analysis computed, a
||| solve unit), each a count of work the compiler did.
module Scale

import Data.List
import Data.List1
import Data.Maybe
import Data.SortedMap
import Data.String
import Data.Vect
import System

import IdrisMLIR.Spec.Core.Verdict
import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Closures.Declarations
import IdrisMLIR.Spec.Families.Ops
import IdrisMLIR.Spec.Families.Types
import IdrisMLIR.Spec.Functions.Declarations
import IdrisMLIR.Spec.Functions.Tail
import IdrisMLIR.Spec.Ops.Checks
import IdrisMLIR.Spec.Ops.IO
import IdrisMLIR.Spec.Ops.Platform
import IdrisMLIR.Spec.Runtime.Endings

import Facts
import Files
import Trace

%default total

------------------------------------------------------------------------------
-- The fixtures
------------------------------------------------------------------------------

||| The shapes. Each is the program of a wall the compiler once hit:
||| - WideMatch: one function, a match of many cases, every tenth a crash,
|||   each case building and consuming a cell (a graph built per terminator
|||   and successor; a driver revisiting an op of many regions; liveness
|||   asked once per region; ancestor walks per op);
||| - Labels: thousands of closure labels on one key, each capturing a
|||   value of the key, so the key is on a cycle of captures (the label
|||   solve's items, the product of points and labels);
||| - Functions: thousands of functions, a call DAG over one strongly
|||   connected component (state per value over the whole program; a
|||   callee looked up per call; summaries solved per function pair);
||| - Component: one component of M members over R result types, R growing
|||   with M, every call in it a frame (frames cloned per member and
|||   result type, M times R, where a stack per result type is M plus R);
||| - LongFunction: one function of a long chain of values, cells that
|||   never escape among them, and a region every hundred values (a bit
|||   vector per value copied along every edge);
||| - Types: families, half a chain each holding the one before, half
|||   holding the chain's last (a table of data types rebuilt per
|||   declaration; a type's text holding every body it reaches);
||| - Nesting: an `else if` ladder, a match nested in each branch, and a
|||   chain of non-tail calls, through the tools on their own small stack
|||   (a recursion on nesting or call depth in the tools);
||| - NestingSource: the same two shapes as Idris source, through the
|||   frontend and the elaborator.
||| The threads test compiles Functions at one thread and on the pool.
data Fixture = WideMatch | Labels | Functions | Component | LongFunction | Types | Nesting | NestingSource

||| Every fixture, each once, with the name a test calls it by.
fixtures : List (String, Fixture)
fixtures =
  [ ("wide-match", WideMatch), ("labels", Labels), ("functions", Functions)
  , ("component", Component), ("long-function", LongFunction), ("types", Types)
  , ("nesting", Nesting), ("nesting-source", NestingSource) ]

||| The size a fixture is printed at by factor 1. Each is a twentieth to a
||| tenth of the wall's own, which was a module the compiler met; at twice
||| it every compilation must still end within a test's step, so the sizes
||| are a calibration, and the relation, not the size, is what finds a
||| wall.
base : Fixture -> Nat
base WideMatch = 2000
base Labels = 4096
base Functions = 3500
base Component = 100
base LongFunction = 10000
base Types = 700
base Nesting = 5000
base NestingSource = 500

||| How many times the size: the two compilations a relation compares.
data Factor = AtSize | AtTwice

factorOf : String -> Maybe Factor
factorOf "1" = Just AtSize
factorOf "2" = Just AtTwice
factorOf _ = Nothing

scaled : Factor -> Nat -> Nat
scaled AtSize n = n
scaled AtTwice n = 2 * n

------------------------------------------------------------------------------
-- Spelling, from the specification
------------------------------------------------------------------------------

||| The dialect's namespace, as a type's or an attribute's name begins (an
||| op's is the specification's opName).
idr : String
idr = wordText (namespaceWord Idr)

||| A type of the dialect, by its declaration: `!idr.<mnemonic>`.
typeName : TypeDef p -> String
typeName d = "!" ++ idr ++ "." ++ mnemonicText d.mnemonic

||| An attribute of the dialect, by its declaration: `#idr.<mnemonic>`.
attrName : AttrDef p -> String
attrName d = "#" ++ idr ++ "." ++ mnemonicText d.mnemonic

||| A case of a closed set, as the IR spells it.
spelled : Closed a -> a -> String
spelled c x = spellingText (c.describe x)

||| A family's data type, whole: `!idr.data<#F>`. The fixtures' families
||| take no index, and each built value is of a family of one constructor
||| or is refined to the one it is built of.
dataOf : String -> String
dataOf alias = typeName dataType ++ "<#" ++ alias ++ ">"

||| A family's data type refined to one constructor: `!idr.data<#F @C>`.
refinedTo : String -> String -> String
refinedTo alias label = typeName dataType ++ "<#" ++ alias ++ " @" ++ label ++ ">"

||| A closure of one word to one word: `!idr.fn<(i64) -> (i64)>`, each list
||| between its parentheses, as the type's syntax has them.
closure : String
closure = typeName fnType ++ "<(i64) -> (i64)>"

------------------------------------------------------------------------------
-- Printing a program
------------------------------------------------------------------------------

Text : Type
Text = List String

sepBy : String -> List String -> String
sepBy sep = concat . intersperse sep

||| A family declaration's alias: its constructors, each with its fields.
familyDecl : (alias : String) -> List (String, List String) -> Text
familyDecl alias ctors =
  ["#" ++ alias ++ " = " ++ attrName familyAttr ++ "<" ++ show alias ++ " [] {"]
  ++ map (\(label, fields) => "    @" ++ label ++ " (" ++ sepBy ", " fields ++ ")") ctors
  ++ ["}>"]

||| `[0, n)`, counted down onto the list, so no step waits on another.
upTo : Nat -> List Nat
upTo n = go n []
  where
    go : Nat -> List Nat -> List Nat
    go Z acc = acc
    go (S k) acc = go k (k :: acc)

||| `%r` for one result, `%r:k` for several: how a result group is bound.
bindAs : String -> Nat -> String
bindAs r 1 = r
bindAs r k = r ++ ":" ++ show k

||| The results of a group bound as `bindAs` binds them, each by its use.
resultUses : String -> Nat -> List String
resultUses r 1 = [r]
resultUses r k = map (\j => r ++ "#" ++ show j) (upTo k)

||| `T` or `(T, ...)`: a list of result types after an arrow.
resultTypes : List String -> String
resultTypes [t] = t
resultTypes ts = "(" ++ sepBy ", " ts ++ ")"

||| The property a call writes its tail fact under, as the specification
||| names it: the one of the call's attributes whose cases are the tail
||| kinds.
tailFact : String
tailFact = concatMap named (toList callOp.attrs)
  where
    named : Attr -> String
    named (MkAttr n (AProperty (EnumProperty d))) =
      if d.enum.name == (enumDef tailKindClosed).name then identText n else ""
    named _ = ""

||| A call whose result something after it uses, so the call is no tail
||| call, which its fact says.
call : (results : String) -> (callee : String) -> (args : List (String, String)) -> List String -> String
call r callee args results =
  bindAs r (length results) ++ " = " ++ opName callOp ++ " @" ++ callee
  ++ "(" ++ sepBy ", " (map fst args) ++ ") <{" ++ tailFact ++ " = " ++ spelled tailKindClosed NonTail
  ++ "}> : (" ++ sepBy ", " (map snd args) ++ ") -> " ++ resultTypes results

||| ` -> T`, or nothing for a function of no results.
arrow : List String -> String
arrow [] = ""
arrow ts = " -> " ++ resultTypes ts

||| A function of the program: its symbol, parameters, results and body.
func : (name : String) -> List (String, String) -> List String -> Text -> Text
func name params results body =
  [ "  " ++ opName funcOp ++ " @" ++ name ++ "(" ++ sepBy ", " (map (\(v, t) => v ++ ": " ++ t) params) ++ ")"
    ++ arrow results ++ " {" ]
  ++ map ("    " ++) body ++ ["  }"]

||| `idr.return %a, ... : T, ...`.
ret : List String -> List String -> String
ret [] _ = opName returnOp
ret vs ts = opName returnOp ++ " " ++ sepBy ", " vs ++ " : " ++ sepBy ", " ts

||| The constant `k` of a word type.
constant : String -> Integer -> String -> String
constant v k t = v ++ " = arith.constant " ++ show k ++ " : " ++ t

||| A cell built and read back: the value `v` boxed in `#Box`, its field
||| bound to `out`.
boxed : (cell : String) -> (v : String) -> (out : String) -> Text
boxed cell v out =
  [ cell ++ " = " ++ opName conOp ++ "(" ++ v ++ " : i64) : " ++ refinedTo "Box" "MkBox"
  , out ++ " = " ++ opName fieldOp ++ " " ++ cell ++ "[0] : " ++ refinedTo "Box" "MkBox" ++ " -> i64" ]

||| The family of one word every fixture that builds cells builds.
box : Text
box = familyDecl "Box" [("MkBox", ["i64"])]

||| The root: it reads the number of the program's arguments, which no
||| compilation knows, so nothing of the fixture folds away, runs the
||| fixture's entry on it, and writes a character of the result, so the
||| entry's work is used.
root : Text
root = func "main" [] []
  [ "%n = " ++ opName argCount ++ " : () -> i64"
  , call "%r" "entry" [("%n", "i64")] ["i64"]
  , "%c = arith.trunci %r : i64 to i32"
  , opName putCharOp ++ " %c : (i32) -> ()"
  , ret [] [] ]

||| The module: the families' aliases, then the program, rooted at `main`,
||| at the stage the frontend writes.
program : (aliases : Text) -> (functions : Text) -> String
program aliases fns =
  unlines (aliases
           ++ [opName programOp ++ " @main root(@main) stage(" ++ spelled stageClosed Higher ++ ") {"]
           ++ fns ++ root ++ ["}"])

------------------------------------------------------------------------------
-- The shapes
------------------------------------------------------------------------------

||| A function that never returns: a crash of the cause a match with no
||| clause for its value has, at a site of its own.
crashing : String -> Text
crashing name = func name [("%x", "i64")] ["i64"]
  [ opName crashOp ++ " " ++ spelled causeClosed NoClauseMatched ++ " at "
    ++ attrName siteAttr ++ "<\"Scale.idr\", 1, 1, " ++ show name ++ ">" ]

||| WideMatch: `n` cases on the run-time value, each building a cell from
||| it and reading the cell, every tenth crashing instead.
wideMatch : Nat -> String
wideMatch n =
  program box
    (crashing "fail"
     ++ func "entry" [("%x", "i64")] ["i64"]
          ([ "%i = arith.index_cast %x : i64 to index"
           , "%r = scf.index_switch %i -> i64" ]
           ++ concatMap arm (upTo n)
           ++ [ "default {", "  scf.yield %x : i64", "}"
              , "%one = arith.constant 1 : i64"
              , "%s = arith.addi %r, %one : i64"
              , ret ["%s"] ["i64"] ]))
  where
    arm : Nat -> Text
    arm k =
      if mod k 10 == 9
        then [ "case " ++ show k ++ " {"
             , "  " ++ call "%v" "fail" [("%x", "i64")] ["i64"]
             , "  scf.yield %v : i64", "}" ]
        else [ "case " ++ show k ++ " {"
             , "  " ++ constant "%k" (cast k) "i64"
             , "  %a = arith.addi %x, %k : i64" ]
             ++ map ("  " ++) (boxed "%b" "%a" "%v")
             ++ ["  scf.yield %v : i64", "}"]

||| Labels: `n` labels, each a function capturing a closure of the one key
||| every label is a value of, chosen by the run-time value and applied at
||| the end of a loop that grows the closure one label a step.
labels : Nat -> String
labels n =
  program []
    (func "base" [("%x", "i64")] ["i64"] [ret ["%x"] ["i64"]]
     ++ concatMap label (upTo n)
     ++ func "grow" [("%k", closure), ("%x", "i64")] [closure]
          ([ "%i = arith.index_cast %x : i64 to index"
           , "%r = scf.index_switch %i -> " ++ closure ]
           ++ concatMap arm (upTo n)
           ++ [ "default {", "  scf.yield %k : " ++ closure, "}"
              , ret ["%r"] [closure] ])
     ++ func "loop" [("%k", closure), ("%x", "i64")] ["i64"]
          [ "%zero = arith.constant 0 : i64"
          , "%one = arith.constant 1 : i64"
          , "%done = arith.cmpi eq, %x, %zero : i64"
          , "%r = scf.if %done -> (i64) {"
          , "  %y = " ++ opName applyOp ++ " %k(%x) : " ++ closure
          , "  scf.yield %y : i64"
          , "} else {"
          , "  " ++ call "%g" "grow" [("%k", closure), ("%x", "i64")] [closure]
          , "  %m = arith.subi %x, %one : i64"
          , "  " ++ call "%y" "loop" [("%g", closure), ("%m", "i64")] ["i64"]
          , "  %z = arith.addi %y, %one : i64"
          , "  scf.yield %z : i64"
          , "}"
          , ret ["%r"] ["i64"] ]
     ++ func "entry" [("%x", "i64")] ["i64"]
          [ "%b = " ++ opName closureOp ++ " @base() : () -> " ++ closure
          , call "%r" "loop" [("%b", closure), ("%x", "i64")] ["i64"]
          , "%one = arith.constant 1 : i64"
          , "%s = arith.addi %r, %one : i64"
          , ret ["%s"] ["i64"] ])
  where
    labelName : Nat -> String
    labelName k = "l" ++ show k
    label : Nat -> Text
    label k = func (labelName k) [("%k", closure), ("%x", "i64")] ["i64"] [ret ["%x"] ["i64"]]
    arm : Nat -> Text
    arm k =
      [ "case " ++ show k ++ " {"
      , "  %c = " ++ opName closureOp ++ " @" ++ labelName k ++ "(%k) : (" ++ closure ++ ") -> " ++ closure
      , "  scf.yield %c : " ++ closure, "}" ]

||| A function that adds one to what a call gives back, so the call is no
||| tail call: `name(x) = callee(x) + 1`, or, with no callee, `x`.
step : (name : String) -> Maybe String -> Text
step name Nothing = func name [("%x", "i64")] ["i64"] [ret ["%x"] ["i64"]]
step name (Just callee) = func name [("%x", "i64")] ["i64"]
  [ call "%r" callee [("%x", "i64")] ["i64"]
  , "%one = arith.constant 1 : i64"
  , "%s = arith.addi %r, %one : i64"
  , ret ["%s"] ["i64"] ]

||| Functions: `n` functions in a binary DAG, each calling its two
||| children, the leaves calling into one component of `n / 70` members
||| that call round it while their argument counts down.
functions : Nat -> String
functions n =
  program [] (concatMap node (upTo n) ++ concatMap member (upTo members)
              ++ step "entry" (Just "f0"))
  where
    members : Nat
    members = max 1 (div n 70)
    member : Nat -> Text
    member j = func ("g" ++ show j) [("%x", "i64")] ["i64"]
      [ "%zero = arith.constant 0 : i64"
      , "%one = arith.constant 1 : i64"
      , "%done = arith.cmpi eq, %x, %zero : i64"
      , "%r = scf.if %done -> (i64) {"
      , "  " ++ constant "%j" (cast j) "i64"
      , "  scf.yield %j : i64"
      , "} else {"
      , "  %m = arith.subi %x, %one : i64"
      , "  " ++ call "%y" ("g" ++ show (mod (S j) members)) [("%m", "i64")] ["i64"]
      , "  %z = arith.addi %y, %one : i64"
      , "  scf.yield %z : i64"
      , "}"
      , ret ["%r"] ["i64"] ]
    node : Nat -> Text
    node i =
      let left = 2 * i + 1
          right = 2 * i + 2
      in if right < n
           then func ("f" ++ show i) [("%x", "i64")] ["i64"]
                  [ call "%a" ("f" ++ show left) [("%x", "i64")] ["i64"]
                  , call "%b" ("f" ++ show right) [("%x", "i64")] ["i64"]
                  , "%s = arith.addi %a, %b : i64"
                  , ret ["%s"] ["i64"] ]
           else step ("f" ++ show i) (Just ("g" ++ show (mod i members)))

||| The words a component's result types are made of.
wordTypes : List1 String
wordTypes = "i64" ::: ["i32", "i16", "i8"]

||| Result type `r`: one to as many words as it takes, the word cycling,
||| so every type up to `r` differs.
resultsOf : Nat -> List String
resultsOf r = replicate (S (div r 4)) (wordAt (mod r 4) (forget wordTypes))
  where
    wordAt : Nat -> List String -> String
    wordAt _ [w] = w
    wordAt Z (w :: _) = w
    wordAt (S k) (_ :: ws) = wordAt k ws
    wordAt _ [] = "i64"

||| `v` of word type `w` as an i64 into `out`, or `v` itself when `w` is.
widenFrom : (out : String) -> (v : String) -> (w : String) -> (String, Text)
widenFrom out v "i64" = (v, [])
widenFrom out v w = (out, [out ++ " = arith.extsi " ++ v ++ " : " ++ w ++ " to i64"])

||| `v`, an i64, as word type `w` into `out`, or `v` itself when `w` is.
narrowTo : (out : String) -> (v : String) -> (w : String) -> (String, Text)
narrowTo out v "i64" = (v, [])
narrowTo out v w = (out, [out ++ " = arith.trunci " ++ v ++ " : i64 to " ++ w])

||| Component: `m` members on one cycle over `div m 10` result types, each
||| calling the next and returning a value of its own type built from the
||| next's, so every call of the cycle is a frame of the caller's type.
component : Nat -> String
component m =
  program [] (concatMap member (upTo m) ++ step "entry" (Just "c0"))
  where
    kinds : Nat
    kinds = max 1 (div m 10)
    memberName : Nat -> String
    memberName i = "c" ++ show i
    member : Nat -> Text
    member i =
      let mine = resultsOf (mod i kinds)
          next = mod (S i) m
          theirs = resultsOf (mod next kinds)
          first = fromMaybe "i64" (head' theirs)
          (wide, widening) = widenFrom "%w" (fromMaybe "%y" (head' (resultUses "%y" (length theirs)))) first
          outs = map (\(j, w) => narrowTo ("%o" ++ show j) "%s" w) (zip (upTo (length mine)) mine)
          consts = map (\(j, w) => constant ("%k" ++ show j) (cast (mod i 100)) w) (zip (upTo (length mine)) mine)
      in func (memberName i) [("%x", "i64")] mine
           ([ "%zero = arith.constant 0 : i64"
            , "%one = arith.constant 1 : i64"
            , "%done = arith.cmpi eq, %x, %zero : i64"
            , bindAs "%r" (length mine) ++ " = scf.if %done -> (" ++ sepBy ", " mine ++ ") {" ]
            ++ map ("  " ++) consts
            ++ [ "  scf.yield " ++ sepBy ", " (map (\j => "%k" ++ show j) (upTo (length mine)))
                 ++ " : " ++ sepBy ", " mine
               , "} else {"
               , "  %m = arith.subi %x, %one : i64"
               , "  " ++ call "%y" (memberName next) [("%m", "i64")] theirs ]
            ++ map ("  " ++) widening
            ++ [ "  %s = arith.addi " ++ wide ++ ", %one : i64" ]
            ++ map ("  " ++) (concatMap snd outs)
            ++ [ "  scf.yield " ++ sepBy ", " (map fst outs) ++ " : " ++ sepBy ", " mine
               , "}"
               , ret (resultUses "%r" (length mine)) mine ])

||| LongFunction: one function of `n` steps, each boxing the running value
||| in a cell that never escapes, reading it back and adding one; every
||| hundredth step chooses between two values in a region.
longFunction : Nat -> String
longFunction n =
  program box
    (func "entry" [("%x", "i64")] ["i64"]
       (["%one = arith.constant 1 : i64", "%v0 = arith.addi %x, %one : i64"]
        ++ concatMap stepAt (upTo n)
        ++ [ret ["%v" ++ show n] ["i64"]]))
  where
    stepAt : Nat -> Text
    stepAt k =
      let here = "%v" ++ show k
          next = "%v" ++ show (S k)
      in if mod k 100 == 99
           then [ "%t" ++ show k ++ " = arith.cmpi slt, " ++ here ++ ", %x : i64"
                , next ++ " = scf.if %t" ++ show k ++ " -> (i64) {"
                , "  scf.yield " ++ here ++ " : i64"
                , "} else {"
                , "  scf.yield %x : i64"
                , "}" ]
           else boxed ("%b" ++ show k) here ("%f" ++ show k)
                ++ [next ++ " = arith.addi %f" ++ show k ++ ", %one : i64"]

||| Types: `div n 2` families in a chain, each holding the one before, and
||| as many holding the chain's last; a function builds each, and the entry
||| builds every one of the second half and reads a field of each.
types : Nat -> String
types n =
  program (concatMap chainFamily (upTo half) ++ concatMap holder (upTo half))
    (concatMap makeChain (upTo half) ++ concatMap makeHolder (upTo half)
     ++ func "entry" [("%x", "i64")] ["i64"]
          (["%acc0 = arith.constant 0 : i64"]
           ++ concatMap readHolder (upTo half)
           ++ [ret ["%acc" ++ show half] ["i64"]]))
  where
    half : Nat
    half = max 1 (div n 2)
    chainName : Nat -> String
    chainName k = "F" ++ show k
    holderName : Nat -> String
    holderName k = "G" ++ show k
    chainLast : String
    chainLast = chainName (pred half)
    chainFamily : Nat -> Text
    chainFamily Z = familyDecl (chainName Z) [("Mk", ["i64"])]
    chainFamily (S k) = familyDecl (chainName (S k)) [("Mk", ["i64", dataOf (chainName k)])]
    holder : Nat -> Text
    holder k = familyDecl (holderName k) [("Mk", ["i64", dataOf chainLast])]
    makeChain : Nat -> Text
    makeChain Z = func ("make" ++ chainName Z) [("%x", "i64")] [dataOf (chainName Z)]
      [ "%v = " ++ opName conOp ++ "(%x : i64) : " ++ dataOf (chainName Z)
      , ret ["%v"] [dataOf (chainName Z)] ]
    makeChain (S k) = func ("make" ++ chainName (S k)) [("%x", "i64")] [dataOf (chainName (S k))]
      [ call "%p" ("make" ++ chainName k) [("%x", "i64")] [dataOf (chainName k)]
      , "%v = " ++ opName conOp ++ "(%x : i64, %p : " ++ dataOf (chainName k) ++ ") : " ++ dataOf (chainName (S k))
      , ret ["%v"] [dataOf (chainName (S k))] ]
    makeHolder : Nat -> Text
    makeHolder k = func ("make" ++ holderName k) [("%x", "i64")] [dataOf (holderName k)]
      [ call "%p" ("make" ++ chainLast) [("%x", "i64")] [dataOf chainLast]
      , "%v = " ++ opName conOp ++ "(%x : i64, %p : " ++ dataOf chainLast ++ ") : " ++ dataOf (holderName k)
      , ret ["%v"] [dataOf (holderName k)] ]
    readHolder : Nat -> Text
    readHolder k =
      [ call ("%h" ++ show k) ("make" ++ holderName k) [("%x", "i64")] [dataOf (holderName k)]
      , "%e" ++ show k ++ " = " ++ opName fieldOp ++ " %h" ++ show k ++ "[0] : " ++ dataOf (holderName k) ++ " -> i64"
      , "%acc" ++ show (S k) ++ " = arith.addi %acc" ++ show k ++ ", %e" ++ show k ++ " : i64" ]

||| Nesting: a ladder of `n` comparisons, each `else` holding the next, the
||| innermost giving the argument back; and a chain of `2 * n` functions,
||| each adding one to what the next gives back. The ladder's text is
||| written at one indent, so it grows with the depth and no faster.
nesting : Nat -> String
nesting n =
  program []
    (func "ladder" [("%x", "i64")] ["i64"]
       (concatMap opening (upTo n) ++ ["scf.yield %x : i64"] ++ concatMap closing (reverse (upTo n))
        ++ [ret ["%r0"] ["i64"]])
     ++ concatMap link (upTo chain)
     ++ func "entry" [("%x", "i64")] ["i64"]
          [ call "%a" "ladder" [("%x", "i64")] ["i64"]
          , call "%b" "h0" [("%x", "i64")] ["i64"]
          , "%s = arith.addi %a, %b : i64"
          , ret ["%s"] ["i64"] ])
  where
    chain : Nat
    chain = 2 * n
    opening : Nat -> Text
    opening k =
      [ constant ("%k" ++ show k) (cast k) "i64"
      , "%t" ++ show k ++ " = arith.cmpi eq, %x, %k" ++ show k ++ " : i64"
      , "%r" ++ show k ++ " = scf.if %t" ++ show k ++ " -> (i64) {"
      , "scf.yield %k" ++ show k ++ " : i64"
      , "} else {" ]
    closing : Nat -> Text
    closing Z = ["}"]
    closing (S j) = ["}", "scf.yield %r" ++ show (S j) ++ " : i64"]
    link : Nat -> Text
    link k = step ("h" ++ show k) (if S k < chain then Just ("h" ++ show (S k)) else Nothing)

||| NestingSource: the same shapes as Idris source: a ladder of `n` `else
||| if`s and a chain of `n` functions each adding one to the next's.
nestingSource : Nat -> String
nestingSource n =
  unlines
    ([ "module Main", "", "import Prelude", ""
     , "ladder : Int -> Int", "ladder x =" ]
     ++ map rung (upTo n) ++ ["  x", ""]
     ++ concatMap link (upTo n)
     ++ [ "main : IO ()", "main = do", "  c <- getChar"
        , "  let x = cast (ord c)", "  printLn (ladder x + h0 x)" ])
  where
    rung : Nat -> String
    rung k = "  if x == " ++ show k ++ " then " ++ show k ++ " else"
    link : Nat -> Text
    link k =
      let name = "h" ++ show k in
      [ name ++ " : Int -> Int"
      , name ++ " x = " ++ (if S k < n then "1 + h" ++ show (S k) ++ " x" else "x"), "" ]

||| The text of a fixture at a size.
printed : Fixture -> Nat -> String
printed WideMatch = wideMatch
printed Labels = labels
printed Functions = functions
printed Component = component
printed LongFunction = longFunction
printed Types = types
printed Nesting = nesting
printed NestingSource = nestingSource

||| What a fixture is printed as: Idris source for the frontend, or a module
||| of the dialect.
data Printed = IdrisSource | DialectModule

printedAs : Fixture -> Printed
printedAs WideMatch = DialectModule
printedAs Labels = DialectModule
printedAs Functions = DialectModule
printedAs Component = DialectModule
printedAs LongFunction = DialectModule
printedAs Types = DialectModule
printedAs Nesting = DialectModule
printedAs NestingSource = IdrisSource

||| The file what is printed so is printed into.
printedFile : Printed -> String
printedFile IdrisSource = "Main.idr"
printedFile DialectModule = "scale.mlir"

||| The file a fixture is printed into, by what it is printed as; none for
||| a name that is no fixture's.
export
sourceFileOf : (name : String) -> Maybe String
sourceFileOf name = printedFile . printedAs <$> lookup name fixtures

||| `--scale-print <fixture> <factor>`: the fixture at its size times the
||| factor, or nothing for a name or factor that is none.
export
printOf : List String -> Maybe String
printOf [name, k] = do
  f <- lookup name fixtures
  factor <- factorOf k
  pure (printed f (scaled factor (base f)))
printOf _ = Nothing

------------------------------------------------------------------------------
-- The relation
------------------------------------------------------------------------------

||| What a compilation's report says, as far as a relation reads it: its
||| verdict, none where the report spells none, and each statistic,
||| `<pass>.<counter>`, with its sum.
record Report where
  constructor MkReport
  verdict : Maybe CompilerVerdict
  statistics : SortedMap String Integer

||| The report idris-mlir writes under --report: a `verdict:` line, and a
||| `statistic: <key>=<sum>` line per statistic, the key holding no `=`.
reportOf : String -> Report
reportOf text = foldl line (MkReport Nothing empty) (lines text)
  where
    line : Report -> String -> Report
    line r l = case words l of
      ["verdict:", v] => { verdict := readVerdict v } r
      ["statistic:", kv] =>
        case break (== '=') (unpack kv) of
          (k, '=' :: v) => case parseInteger (pack v) of
            Nothing => r
            Just n => { statistics $= insert (pack k) n } r
          _ => r
      _ => r

||| One count at the two sizes.
record Measure where
  constructor MkMeasure
  name : String
  atOnce : Integer
  atTwice : Integer

||| A count at twice the size within 2.2 times its count at the size: one
||| in proportion to the program doubles, and the tenth beyond it leaves
||| room for the part of a compilation that does not grow with the
||| program; a quadratic is four times. The factor is a first reading, to
||| be calibrated on the first runs. A count of 16 or fewer at twice the
||| size says nothing of growth, so it holds.
withinRelation : Measure -> Bool
withinRelation m = m.atTwice <= 16 || 10 * m.atTwice <= 22 * m.atOnce

||| Every key of either map, with its count at each size, 0 where absent.
measures : (kind : String) -> SortedMap String Integer -> SortedMap String Integer -> List Measure
measures kind once twice =
  map (\k => MkMeasure (kind ++ " " ++ k) (fromMaybe 0 (lookup k once)) (fromMaybe 0 (lookup k twice)))
      (nub (keys once ++ keys twice))

||| Whether some statistic of the report is of the kind its counter's name
||| ends with: each solve's work (`.work`) and each pass's footprint
||| (`.footprint`), which the relation reads like every other counter.
declares : String -> Report -> Bool
declares suffix r = any (isSuffixOf suffix) (keys r.statistics)

||| Whether a report's verdict is that the program compiled.
accepted : Maybe CompilerVerdict -> Bool
accepted (Just VerdictAccepted) = True
accepted _ = False

||| A report's verdict as the report spells it.
verdictText : Maybe CompilerVerdict -> String
verdictText = maybe "none" verdictWords

||| `--scale-check <report> <trace> <report> <trace>`: the compilation at
||| the size and at twice it, both accepted, and every count of the second
||| within the relation of the first's; one line per broken count, naming
||| it with both counts, and exit 1 if any.
covering export
scaleCheck : List String -> IO ()
scaleCheck [reportOnce, traceOnce, reportTwice, traceTwice] = do
  once <- reportOf <$> readOrDie reportOnce
  twice <- reportOf <$> readOrDie reportTwice
  zonesOnce <- zoneCounts traceOnce
  zonesTwice <- zoneCounts traceTwice
  let verdicts = accepted once.verdict && accepted twice.verdict
  putStrLn (if verdicts then "verdict: accepted at both sizes"
            else "verdict: " ++ verdictText once.verdict ++ " at the size, " ++ verdictText twice.verdict ++ " at twice it")
  let counted = measures "statistic" once.statistics twice.statistics
                ++ measures "zone" zonesOnce zonesTwice
      broken = filter (not . withinRelation) counted
  if null (keys zonesOnce)
     then putStrLn "zones: none counted, so the trace measured nothing"
     else if null broken
       then putStrLn "relation: every count at twice the size within 2.2 times its count at the size"
       else do
         putStrLn "relation: counts beyond 2.2 times their count at the size:"
         for_ broken $ \m => putStrLn ("  " ++ m.name ++ ": " ++ show m.atOnce ++ " at the size, "
                                       ++ show m.atTwice ++ " at twice it")
  let work = declares ".work" once && declares ".work" twice
  putStrLn (if work then "work: each solve's count read"
            else "work: no solve reports its count (a `<pass>.work` statistic per solve, declared with its pass)")
  let footprint = declares ".footprint" once && declares ".footprint" twice
  putStrLn (if footprint then "footprint: each pass's read"
            else "footprint: no pass reports its footprint (a `<pass>.footprint` statistic per pass)")
  unless (verdicts && not (null (keys zonesOnce)) && null broken && work && footprint) $ exitWith (ExitFailure 1)
scaleCheck _ = do
  putStrLn "usage: runtests --scale-check <report> <trace> <report> <trace>"
  exitWith (ExitFailure 2)
