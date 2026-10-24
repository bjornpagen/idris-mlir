-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| idr-expect's properties, one record each: the one list of what a test
||| may state of a module by name; and --idr-contracts' relations, one
||| record each: the one list of what every pass keeps between the module
||| before it and the module after it. The C++ table of both is printed
||| from them (`table`, committed as
||| foreign/idr/include/idr/Transforms/ExpectProperties.inc and compared by
||| tests/expect-table-current), so a property's name, the
||| shape of its argument and the check that runs it, and a relation's name,
||| its check and how the contracts' test pass breaks it, are written once,
||| here.
|||
||| Each property reads facts the dialect declares (an interface, a trait,
||| the effect system's one query, a type), never a list of ops, so a
||| property survives an op renamed, split or merged. Its sentence is what
||| it checks; the C++ check carries it out.
module Properties

import Data.List
import Data.List1
import Data.So
import Data.String

import IdrisMLIR.Spec.Core.Text
import IdrisMLIR.Spec.Generator.Render

%default total

------------------------------------------------------------------------------
-- What a record holds
------------------------------------------------------------------------------

||| Whether `s` is a property's name: lower-case snake words joined by
||| single dashes, `counts-nothing`.
public export
isName : String -> Bool
isName s = allSnake (forget (split (== '-') s))

||| A property's name, word by word: what a test writes, and, read in lower
||| camel case, the C++ name of the check that runs it, so the two cannot
||| disagree.
public export
data Name : Type where
  MkName : (words : List1 Word) -> Name

namespace Name
  ||| A literal name, split at its dashes, each word proved snake.
  public export
  fromString : (s : String) -> {auto 0 ok : So (isName s)} -> Name
  fromString s = MkName (segments (mnemonicOf (split (== '-') s) ok))

||| The name as a test writes it.
export
nameText : Name -> String
nameText (MkName ws) = joinBy "-" (map wordText (forget ws))

||| The C++ name of the check: the first word, then each other word in
||| upper camel case, `countsNothing`.
export
checkName : Name -> String
checkName (MkName (w ::: ws)) = wordText w ++ concatMap camel ws

||| The name in upper camel case, every word: a relation's enumerator,
||| `LinearKept`.
export
camelName : Name -> String
camelName (MkName ws) = concatMap camel (forget ws)

||| The shape of a property's argument: what follows `=` in a request, read
||| into a typed value before the check runs (ExpectArguments.h).
public export
data Shape : Type where
  ||| No argument: the property alone.
  NoArgument : Shape
  ||| `@f`: every function made from f, at least one.
  OfFunctions : Shape
  ||| `@f` or nothing: those functions, or the whole module.
  OfScope : Shape
  ||| `@f`: a name, which may name no function of the module.
  OfSymbol : Shape
  ||| `@f:@g`: the functions @f names, and the name @g.
  OfPair : Shape

||| The C++ type a shape's argument is read into.
export
shapeType : Shape -> String
shapeType NoArgument = "Nothing"
shapeType OfFunctions = "Functions"
shapeType OfScope = "Roots"
shapeType OfSymbol = "Symbol"
shapeType OfPair = "Pair"

||| A shape whose argument has a value for the whole program, which the
||| contracts pass when they check a property of every compilation: no
||| argument, every function, or the whole module.
public export
data Whole : Shape -> Type where
  WholeOfNothing : Whole NoArgument
  EveryFunction : Whole OfFunctions
  WholeModule : Whole OfScope

||| Who states a property, and what makes it fail.
public export
data Role : Type where
  ||| A test states it of its module, and a fixture's module makes it fail.
  Stated : Role
  ||| A test states it, and only a defect of the compiler makes it fail: it
  ||| holds an answer of the compiler to a second derivation of it, so no
  ||| module of a fixture can make the two disagree.
  SelfCheck : Role
  ||| The contracts check it of every compilation, of the whole program; a
  ||| fixture's module makes it fail.
  Universal : Role

||| A role a property of a shape may have: a universal property needs a
||| whole-program argument.
public export
data Fits : Shape -> Role -> Type where
  StatedFits : Fits s Stated
  SelfCheckFits : Fits s SelfCheck
  UniversalFits : Whole s -> Fits s Universal

||| One property: its name, its argument's shape, its role, and the
||| sentence that says what it checks, a line at a time.
public export
record Property where
  constructor MkProperty
  name : Name
  shape : Shape
  role : Role
  0 fits : Fits shape role
  says : List Line

||| A property, its role checked against its shape where it is written.
public export
property : Name -> (shape : Shape) -> (role : Role) -> {auto 0 fits : Fits shape role}
        -> List Line -> Property
property n shape role says = MkProperty n shape role fits says

------------------------------------------------------------------------------
-- The properties
------------------------------------------------------------------------------

||| Every property, in the table's order.
export
properties : List Property
properties =
  [ property "counts-nothing" OfFunctions Stated
      [ "No op of @f but a call reads or writes a count: no reference is"
      , "counted in it, and none is freed by a test of its count." ]
  , property "tests-nothing" OfFunctions Stated
      [ "@f tests no sharing at run time: no op of it reads a count it does"
      , "not write, every reuse token of it holds its cell, so none is"
      , "tested for null, and some cell is taken apart in it." ]
  , property "reuses-in-place" OfFunctions Stated
      [ "Every cell @f fills is made from a reuse token, no heap memory"
      , "acquired for it, and @f fills one." ]
  , property "reuses-every-cell" OfFunctions Stated
      [ "No op of @f frees the cell a reuse token holds: every cell it takes"
      , "apart is filled again." ]
  , property "resets-unshared" OfScope Stated
      [ "No value whose sharing is tested at run time, in @f or anywhere, is"
      , "one its function gives another reference: each test finds its cell"
      , "unshared." ]
  , property "builds-nothing" OfFunctions Stated
      [ "No op of @f but a call builds a value in memory: none acquires"
      , "memory or writes the contents of a cell, as its declaration says;"
      , "what @f returns or holds is its parameters' or static data." ]
  , property "no-heap-allocation" OfScope Stated
      [ "No op acquires heap memory, anywhere, or in @f and every function"
      , "it may call, as the effect system's declaration of each op says." ]
  , property "one-clone" OfSymbol Stated
      [ "Every call of @f, or of a copy of it, calls one function, and there"
      , "is one." ]
  , property "not-called" OfSymbol Stated
      [ "No call of @f, or of a copy of it, is left; a function the module"
      , "never had is not called either." ]
  , property "specialized-once" OfFunctions Stated
      [ "Every copy of @f but @f calls, of @f and its copies, only itself"
      , "and @f: a recursion's specializations stop after one step." ]
  , property "contified" NoArgument Stated
      [ "In a first-order program, no function is called once, from a"
      , "function it calls back: each continuation is part of what it"
      , "continues." ]
  , property "reached" NoArgument Stated
      [ "Every function of the program is reached from its roots, the"
      , "functions its symbol table makes public, by the symbols the bodies"
      , "of the functions reached before it name." ]
  , property "calls" OfPair Stated
      [ "Some call in @f calls @g or a copy of it; after lowering @g may be"
      , "a function of the runtime, named by its symbol." ]
  , property "tail-calls" OfPair Stated
      [ "Some call in @f of @g or a copy of it is a tail call, which goes in"
      , "its caller's place: a fact of the program's calls, before lowering." ]
  , property "results-as-given" OfPair Stated
      [ "Every call in @f of @g or a copy of it gives each result laid out as"
      , "its callee returns it, and no op after the call re-packs one, where"
      , "@f takes it or on its way to @f's return: none converts it between"
      , "two layouts." ]
  , property "folded" OfFunctions Stated
      [ "No op left in a copy of @f is one a fold would replace: one with"
      , "results, no memory effect, no call and no constant of its own, whose"
      , "operands are constants alone." ]
  , property "no-guards" OfFunctions Stated
      [ "No guard is left in @f: every condition its partial primitives need"
      , "is proven where it runs." ]
  , property "may-diverge" OfFunctions Stated
      [ "Every function of @f, its copies among them, may never end, as its"
      , "row says: the row holds divergence, which a loop Idris did not prove"
      , "to end puts there wherever a pass moves it, as a call of a function"
      , "that may never end does: a fact of the program's functions, before"
      , "lowering." ]
  , property "word-loop" OfFunctions Stated
      [ "Some loop of @f computes on words alone: no value defined or bound"
      , "in it is a big or a natural." ]
  , property "in-place" OfScope Stated
      [ "Once arrays are buffers, nothing copies a buffer, in @f or"
      , "anywhere, and a buffer is there." ]
  , property "moves-out" OfScope Stated
      [ "Some element of an array is rebuilt in its place, in @f or"
      , "anywhere, moved out with the reference the array held." ]
  , property "writes-forwarded" OfScope Stated
      [ "In a program whose references are not yet counted, no read of"
      , "mutable memory, in @f or anywhere, reads the element the write"
      , "right before it wrote, only computation between: the read is the"
      , "value written, unless Idris proved it used once or it cannot stand"
      , "for the read's." ]
  , property "overwrites-dropped" OfScope Stated
      [ "In a program whose references are not yet counted, no write of"
      , "mutable memory, in @f or anywhere, is followed by a write of its"
      , "element, only computation between: what nothing read goes, unless"
      , "Idris proved its value used once." ]
  , property "structured-loops" OfScope Stated
      [ "No op of the arrays' generating set is left, in @f or anywhere,"
      , "and some structured op is there." ]
  , property "vectorized" OfScope Stated
      [ "Some loop computes on vectors, and no linalg.generic with a"
      , "parallel dimension and a body of words alone is left scalar." ]
  , property "narrowed-lanes" OfScope Stated
      [ "Some loop computes integer lanes in 32 bits or fewer, and every loop"
      , "that computes wider integer lanes, a reduction's accumulator aside,"
      , "and may run more than once is the 64-bit version beside one that"
      , "computes its lanes in 32." ]
  , property "constant-stack" OfFunctions Universal
      [ "No recursion from @f grows the stack: every function it may call"
      , "that is on a cycle of references refers to the others of its cycle"
      , "only by guaranteed tail calls (musttail)." ]
  , property "labels-least" NoArgument SelfCheck
      [ "The label solve's set at every point is the least the program's"
      , "statements give it, derived again a label at a time from them." ]
  ]

------------------------------------------------------------------------------
-- The contracts' relations
------------------------------------------------------------------------------

||| One relation --idr-contracts checks after every pass, between the
||| module before it and the module after it: its name, the sentence that
||| says what it holds, a line at a time, and how the contracts' test pass
||| breaks it on purpose, which that pass's option shows as the help of the
||| relation's value.
public export
record Relation where
  constructor MkRelation
  name : Name
  says : List Line
  breaks : Line

||| Every relation, in the order the contracts check them.
export
relations : List Relation
relations =
  [ MkRelation "quantities-kept"
      [ "Every binder Idris bound has the uses Idris proved of it, wherever"
      , "a pass carried it: it is known by its identity, which passes copy"
      , "with it." ]
      "trade the identities of two binders of other uses"
  , MkRelation "linear-kept"
      [ "Every parameter and every result of a function the pass kept is"
      , "where its record says, at its uses: each position the function had"
      , "stands for a run of positions after the pass, in order, each at its"
      , "uses, none only where the pass dropped one used many times." ]
      "drop each result used many times and give each linear result back unrestricted"
  , MkRelation "crash-sites-not-added"
      [ "A function the pass kept whose row could not crash before it has"
      , "no place that may crash after it." ]
      "make every function that could not crash crash"
  , MkRelation "cycle-divergence-kept"
      [ "Every member of a cycle of calls Idris did not prove holds the"
      , "cycle's divergence in its row, which no function's own check sees." ]
      "drop divergence from every member of one cycle Idris did not prove, and from their calls"
  ]

------------------------------------------------------------------------------
-- The table
------------------------------------------------------------------------------

||| The macro a row of a role is written with.
macroOf : Role -> String
macroOf Stated = "IDR_EXPECT_PROPERTY"
macroOf SelfCheck = "IDR_EXPECT_SELF_CHECK"
macroOf Universal = "IDR_EXPECT_UNIVERSAL"

||| A property's rows: its sentence as comments, then its macro.
rowsOf : Property -> List String
rowsOf p =
  map (\l => "// " ++ lineText l) p.says
  ++ [ macroOf p.role ++ "(\"" ++ nameText p.name ++ "\", " ++ shapeType p.shape ++ ", "
         ++ checkName p.name ++ ")" ]

||| A relation's rows: its sentence as comments, then its macro: its name,
||| its enumerator, its check, the test pass's breaker of it and how that
||| breaks it, the C++ names read off its name as a property's check's is.
relationRowsOf : Relation -> List String
relationRowsOf r =
  map (\l => "// " ++ lineText l) r.says
  ++ [ "IDR_CONTRACT_RELATION(\"" ++ nameText r.name ++ "\", " ++ camelName r.name ++ ", "
         ++ checkName r.name ++ ", break" ++ camelName r.name ++ ", " ++ quoted (lineText r.breaks)
         ++ ")" ]

||| What the table says of itself, before its rows.
heading : List String
heading =
  [ "// SPDX-License-Identifier: 0BSD"
  , "// Copyright (c) 2026 Bjorn Pagen"
  , "// idr-expect's properties and --idr-contracts' relations, printed by the"
  , "// test runner (runtests --expect-table) from harness/Properties.idr,"
  , "// their one list; written again and compared by"
  , "// tests/expect-table-current. Each section is read where its first macro"
  , "// is defined, and then needs each of its macros: an includer defines"
  , "// those of the section it reads before it includes this. The"
  , "// properties', (name, argument shape, check):"
  , "//   IDR_EXPECT_PROPERTY   a test states it; a fixture makes it fail;"
  , "//   IDR_EXPECT_SELF_CHECK a test states it; only a defect makes it fail;"
  , "//   IDR_EXPECT_UNIVERSAL  the contracts check it of every compilation."
  , "// The relations', in the order the contracts check them, (name,"
  , "// enumerator, check, the test pass's breaker, how that breaks it):"
  , "//   IDR_CONTRACT_RELATION the contracts check it after every pass."
  , "" ]

||| A section of the table, read where `first`, its first macro, is defined.
section : (first : String) -> List (List String) -> List String
section first rows = ["#ifdef " ++ first] ++ intercalate [""] rows ++ ["#endif"]

||| The C++ table, as committed.
export
table : String
table =
  unlines (heading ++ section "IDR_EXPECT_PROPERTY" (map rowsOf properties) ++ [""]
           ++ section "IDR_CONTRACT_RELATION" (map relationRowsOf relations))
