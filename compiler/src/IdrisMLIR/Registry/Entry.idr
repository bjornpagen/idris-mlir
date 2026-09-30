||| What an entry of the registry is: the
||| key the compiler knows a library definition by, the shape it expects
||| the definition to have, and the hook, what the compiler does with it.
module IdrisMLIR.Registry.Entry

import IdrisMLIR.Registry.Name
import IdrisMLIR.Rule
import IdrisMLIR.Types

import Data.List
import Data.String

%default total

------------------------------------------------------------------------------
-- Keys
------------------------------------------------------------------------------

||| A `%foreign` spec as a library declares it for backends: a calling
||| convention and the function it names, `C:idris2_putStr`. The spec is the
||| backend contract; the Idris name and type that declare it are its shape.
public export
record Spec where
  constructor MkSpec
  convention : String
  function : String

export
Show Spec where
  show s = s.convention ++ ":" ++ s.function

||| One of the specs Idris records for a `%foreign` definition, as written:
||| `C:idris2_putStr, libidris2_support, idris_support.h` is the convention
||| `C` and the function `idris2_putStr`.
export
parseSpec : String -> Maybe Spec
parseSpec s = case break (== ':') (unpack s) of
  (conv@(_ :: _), _ :: rest) =>
    let fn = trim (pack (takeWhile (/= ',') rest)) in
    if fn == "" then Nothing else Just (MkSpec (pack conv) fn)
  _ => Nothing

||| How the compiler names library knowledge.
public export
data Key
  = ||| An Idris definition.
    Def QName
  | ||| A `%foreign` spec (Idris's own builtins are the closed type `PrimFn`
    ||| and need no key).
    Foreign Spec
  | ||| A spelling in source, checked before TT exists: elaboration can
    ||| erase what it names from TT.
    Spelling String

export
Eq Key where
  Def a == Def b = a == b
  Foreign a == Foreign b = a.convention == b.convention && a.function == b.function
  Spelling a == Spelling b = a == b
  _ == _ = False

export
Show Key where
  show (Def q) = show q
  show (Foreign s) = show s
  show (Spelling s) = s

------------------------------------------------------------------------------
-- Shapes
------------------------------------------------------------------------------

||| Idris's primitive types, as a shape names them.
public export
data PrimTy = IntP IntTy | IntegerP | CharP | DoubleP | StringP | WorldP

export
Eq PrimTy where
  IntP a == IntP b = a == b
  IntegerP == IntegerP = True
  CharP == CharP = True
  DoubleP == DoubleP = True
  StringP == StringP = True
  WorldP == WorldP = True
  _ == _ = False

export
Show PrimTy where
  show (IntP t) = show t
  show IntegerP = "Integer"
  show CharP = "Char"
  show DoubleP = "Double"
  show StringP = "String"
  show WorldP = "%World"

||| What an entry expects a definition's type to be, compared structurally
||| with its normalised checked type (a fingerprint could not explain a
||| mismatch). Arity, quantities and heads are exact. `Hole` stands for a
||| part the hook does not depend on, such as an implicit argument's type;
||| in a shape found, it stands for a part no shape describes, such as a
||| variable.
public export
data Shape
  = Pi Quantity Shape Shape
  | Head Key (List Shape)
  | Prim PrimTy
  | TypeOfTypes
  | Hole

mutual
  ||| Does a shape found conform to the shape expected?
  export
  conforms : (expected : Shape) -> (found : Shape) -> Bool
  conforms Hole _ = True
  conforms (Pi q a b) (Pi r c d) = q == r && conforms a c && conforms b d
  conforms (Head k as) (Head l bs) = k == l && conformsAll as bs
  conforms (Prim p) (Prim r) = p == r
  conforms TypeOfTypes TypeOfTypes = True
  conforms _ _ = False

  conformsAll : List Shape -> List Shape -> Bool
  conformsAll [] [] = True
  conformsAll (a :: as) (b :: bs) = conforms a b && conformsAll as bs
  conformsAll _ _ = False

mutual
  ||| A shape, in parentheses when it is an argument and needs them.
  showAt : (argument : Bool) -> Shape -> String
  showAt arg (Pi q a b) = parens arg ("(" ++ quantity q ++ "_ : " ++ showAt False a ++ ") -> " ++ showAt False b)
    where
      quantity : Quantity -> String
      quantity QW = ""
      quantity q = show q ++ " "
  showAt arg (Head k []) = show k
  showAt arg (Head k as@(_ :: _)) = parens arg (show k ++ showArguments as)
  showAt arg (Prim p) = show p
  showAt arg TypeOfTypes = "Type"
  showAt arg Hole = "_"

  showArguments : List Shape -> String
  showArguments [] = ""
  showArguments (a :: as) = " " ++ showAt True a ++ showArguments as

  parens : Bool -> String -> String
  parens True s = "(" ++ s ++ ")"
  parens False s = s

||| The one printer of shapes, expected and found alike, in
||| Idris's notation with every binder written: `(0 _ : Type) -> (_ :
||| PrimIO.IO _) -> _`.
export
showShape : Shape -> String
showShape = showAt False

------------------------------------------------------------------------------
-- Hooks
------------------------------------------------------------------------------

||| What a function on naturals computes, as primitives on the representation
||| of `Nat`, a big that is never negative: the meaning Idris's own backends
||| give the Prelude's `Nat` functions instead of their unary recursions.
public export
data NatMeaning
  = ||| The primitive of the arguments: `plus` is `NatAdd`.
    Primitive Prim
  | ||| The primitive of the arguments' Integers, then the natural of its
    ||| Integer: `minus` is the difference, clamped at 0.
    Clamped Prim
  | ||| The comparison of the arguments, as the library function that makes
    ||| a `Bool` of an `Int` gives it: `equalNat` is `intToBool` of `NatCompare
    ||| CEq`.
    Tested Cmp QName
  | ||| The library function on Integers, of the arguments' Integers:
    ||| `compareNat` is `compareInteger`.
    OnIntegers QName

||| What the compiler does with a definition it knows: one constructor per
||| behaviour. Passes match on hooks, never on names, and each hook's
||| handler lives with the pass that meets it.
public export
data Hook
  = ||| An IO primitive of Idris's backend contract: its calls are the
    ||| `idr.io` op of this IO operation. Handler:
    ||| `Frontend.Translate.application`.
    IOCall IOOp
  | ||| The identity on its last argument, its one runtime argument; the
    ||| rest are proofs and types. Handler:
    ||| `Frontend.Translate.application`.
    IdentityOnLastArgument
  | ||| The head of the term Idris hands an IO backend, `unsafePerformIO
    ||| main`, which the compiler writes as world-passing code. Handler:
    ||| `Frontend.Main.compileIO`.
    ProgramRoot
  | ||| A function on naturals whose calls compute what it means on the
    ||| representation of `Nat`, in constant time and stack, instead of its
    ||| unary recursion. Handler: `Frontend.Translate.application`.
    NatOperation NatMeaning
  | ||| Rejected where the user's code uses it, under the rule named:
    ||| a definition the user's definitions refer to, or a spelling in the
    ||| user's source. Handler:
    ||| `Frontend.Profile.checkReachable`, `Frontend.Profile.checkPragmas`.
    Forbidden Rule

||| The only kinds of hook. A `faster` hook is another lowering with the same
||| meaning; a `stricter` hook adds a rejection. Removing a hook may change
||| speed or which programs are rejected, never a program's result.
public export
data Kind = Faster | Stricter

export
Show Kind where
  show Faster = "faster"
  show Stricter = "stricter"

||| Every hook has exactly one kind, by construction.
export
kind : Hook -> Kind
kind (IOCall _) = Faster
kind IdentityOnLastArgument = Faster
kind ProgramRoot = Faster
kind (NatOperation _) = Faster
kind (Forbidden _) = Stricter

------------------------------------------------------------------------------
-- Entries
------------------------------------------------------------------------------

||| What an entry expects to find, by the kind of its key.
public export
data Expect : Key -> Type where
  ||| A definition, at the key's name, whose type has this shape.
  Typed : Shape -> Expect (Def q)
  ||| A definition, at this name, that declares the key's spec and whose type
  ||| has this shape.
  Declared : QName -> Shape -> Expect (Foreign s)
  ||| Nothing: a spelling has no definition to resolve.
  Written : Expect (Spelling s)

||| One entry of a table: what the compiler knows a definition by, what it
||| expects it to be, what it does with it, and the rules the hook's handler
||| implements.
public export
record Entry where
  constructor MkEntry
  key : Key
  expect : Expect key
  hook : Hook
  rules : List Rule

||| Where validation resolves an entry, and the shape it expects there; a
||| spelling is not resolved.
export
site : Entry -> Maybe (QName, Shape)
site e = at e.key e.expect
  where
    at : (k : Key) -> Expect k -> Maybe (QName, Shape)
    at (Def q) (Typed s) = Just (q, s)
    at (Foreign _) (Declared q s) = Just (q, s)
    at (Spelling _) Written = Nothing

||| What validation finds wrong with an entry whose definition is present.
public export
data Mismatch
  = ||| The definition's module is loaded, and the definition is not in it.
    Missing
  | ||| The definition does not declare the entry's spec.
    Undeclared
  | ||| Another definition declares the entry's spec.
    DeclaredBy QName
  | ||| The definition's normalised type, which does not conform.
    Found Shape

||| The message of a shape mismatch: the entry, what it expects and what was
||| found, through one printer.
export
mismatch : Entry -> Mismatch -> String
mismatch e m =
  "the registry's entry " ++ show e.key ++ " (" ++ show (kind e.hook) ++ ") expects " ++ expected ++
  ", but found " ++ found m
  where
    declaring : String
    declaring = case e.key of
      Foreign s => ", declared %foreign " ++ show s
      _ => ""
    expected : String
    expected = case site e of
      Just (q, s) => show q ++ " : " ++ showShape s ++ declaring
      Nothing => show e.key
    found : Mismatch -> String
    found Missing = "no such definition in its module"
    found Undeclared = "a definition that does not declare it"
    found (DeclaredBy q) = "it declared by " ++ show q
    found (Found s) = showShape s
