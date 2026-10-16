-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The alphabet a static argument is written in: the forms of term a
||| symbol names, finitely many, listed, and told apart by their codes. The
||| frontend writes each compile-time argument of an instance in it
||| (`Keys`), and what it writes is the instance's identity.
module IdrisMLIR.Proof.Forms

import public IdrisMLIR.Proof.Requests

import public Data.Fin
import Data.List
import Data.List.Elem
import public Data.Vect
import Decidable.Equality

%default total

||| The shapes of term besides binders and literals: an application, a
||| bound variable (its index the node's number), a name of the context
||| (its address the node's), a hole (its address the node's, its argument
||| count the node's number), an as-pattern, a lazy type, a suspended value, a
||| forced one, an erased term, a universe, a string literal and a double
||| literal (the characters of the string and of the double's print
||| follow), the world, and a runtime value an implementation closes over
||| (its number among those values the symbol's magnitude).
public export
data Shape
  = Applied | Variable | Reference | Hole | AsPattern | LazyType | Suspended | Forced
  | Placeholder | Impossible | Dotted | Universe | Text | Floating | World | Marker

shapeTable : Vect 16 Shape
shapeTable = [ Applied, Variable, Reference, Hole, AsPattern, LazyType, Suspended, Forced
             , Placeholder, Impossible, Dotted, Universe, Text, Floating, World, Marker ]

shapeCode : Shape -> Fin 16
shapeCode Applied = 0
shapeCode Variable = 1
shapeCode Reference = 2
shapeCode Hole = 3
shapeCode AsPattern = 4
shapeCode LazyType = 5
shapeCode Suspended = 6
shapeCode Forced = 7
shapeCode Placeholder = 8
shapeCode Impossible = 9
shapeCode Dotted = 10
shapeCode Universe = 11
shapeCode Text = 12
shapeCode Floating = 13
shapeCode World = 14
shapeCode Marker = 15

shapes : Numbered Shape
shapes = MkNumbered 16 shapeCode (\i => index i Forms.shapeTable) decoded
  where
    decoded : (x : Shape) -> index (shapeCode x) Forms.shapeTable = x
    decoded Applied = Refl
    decoded Variable = Refl
    decoded Reference = Refl
    decoded Hole = Refl
    decoded AsPattern = Refl
    decoded LazyType = Refl
    decoded Suspended = Refl
    decoded Forced = Refl
    decoded Placeholder = Refl
    decoded Impossible = Refl
    decoded Dotted = Refl
    decoded Universe = Refl
    decoded Text = Refl
    decoded Floating = Refl
    decoded World = Refl
    decoded Marker = Refl

export
DecEq Shape where
  decEq = decideNumbered shapes

export
Eq Shape where
  a == b = shapeCode a == shapeCode b

export
Ord Shape where
  compare a b = compare (shapeCode a) (shapeCode b)

||| The binders: a lambda, a let, a pi, a pattern variable, a pattern let
||| and a pattern variable's type.
public export
data Binding = Lambda | LetIn | PiType | Pattern | PatternLet | PatternType

bindingTable : Vect 6 Binding
bindingTable = [Lambda, LetIn, PiType, Pattern, PatternLet, PatternType]

bindingCode : Binding -> Fin 6
bindingCode Lambda = 0
bindingCode LetIn = 1
bindingCode PiType = 2
bindingCode Pattern = 3
bindingCode PatternLet = 4
bindingCode PatternType = 5

bindings : Numbered Binding
bindings = MkNumbered 6 bindingCode (\i => index i Forms.bindingTable) decoded
  where
    decoded : (x : Binding) -> index (bindingCode x) Forms.bindingTable = x
    decoded Lambda = Refl
    decoded LetIn = Refl
    decoded PiType = Refl
    decoded Pattern = Refl
    decoded PatternLet = Refl
    decoded PatternType = Refl

export
DecEq Binding where
  decEq = decideNumbered bindings

export
Eq Binding where
  a == b = bindingCode a == bindingCode b

export
Ord Binding where
  compare a b = compare (bindingCode a) (bindingCode b)

||| How a binder's argument is passed: implicitly, explicitly, by search,
||| or implicitly with a default, which follows.
public export
data Passing = ByUnification | ByHand | BySearch | ByDefault

passingTable : Vect 4 Passing
passingTable = [ByUnification, ByHand, BySearch, ByDefault]

passingCode : Passing -> Fin 4
passingCode ByUnification = 0
passingCode ByHand = 1
passingCode BySearch = 2
passingCode ByDefault = 3

passings : Numbered Passing
passings = MkNumbered 4 passingCode (\i => index i Forms.passingTable) decoded
  where
    decoded : (x : Passing) -> index (passingCode x) Forms.passingTable = x
    decoded ByUnification = Refl
    decoded ByHand = Refl
    decoded BySearch = Refl
    decoded ByDefault = Refl

export
DecEq Passing where
  decEq = decideNumbered passings

export
Eq Passing where
  a == b = passingCode a == passingCode b

export
Ord Passing where
  compare a b = compare (passingCode a) (passingCode b)

||| A character, by its code point, as the high and the low ten bits of
||| it: a code point is below 1088 times 1024.
public export
Glyph : Type
Glyph = (Fin 1088, Fin 1024)

||| A form of term: a shape; a binder, with its quantity and how its
||| argument is passed; an integer literal's primitive type and whether it
||| is negative (its magnitude is the symbol's number); a primitive type; a
||| character spelt out (of a text or a double's print); a character
||| literal. Quantities (0, 1, many) and primitive types are numbered, as
||| the writer of an argument numbers them.
public export
data Form
  = Shaped Shape
  | Bound Binding (Fin 3) Passing
  | IntegerLit (Fin 14) Bool
  | PrimitiveType (Fin 14)
  | Spelt Glyph
  | Character Glyph

-- A form as the sum it is, for listing and deciding it.
Sum : Type
Sum = Either Shape (Either (Binding, (Fin 3, Passing)) (Either (Fin 14, Bool) (Either (Fin 14) (Either Glyph Glyph))))

toSum : Form -> Sum
toSum (Shaped s) = Left s
toSum (Bound b q p) = Right (Left (b, (q, p)))
toSum (IntegerLit t negative) = Right (Right (Left (t, negative)))
toSum (PrimitiveType t) = Right (Right (Right (Left t)))
toSum (Spelt g) = Right (Right (Right (Right (Left g))))
toSum (Character g) = Right (Right (Right (Right (Right g))))

fromSum : Sum -> Form
fromSum (Left s) = Shaped s
fromSum (Right (Left (b, (q, p)))) = Bound b q p
fromSum (Right (Right (Left (t, negative)))) = IntegerLit t negative
fromSum (Right (Right (Right (Left t)))) = PrimitiveType t
fromSum (Right (Right (Right (Right (Left g))))) = Spelt g
fromSum (Right (Right (Right (Right (Right g))))) = Character g

fromToSum : (f : Form) -> fromSum (toSum f) = f
fromToSum (Shaped _) = Refl
fromToSum (Bound _ _ _) = Refl
fromToSum (IntegerLit _ _) = Refl
fromToSum (PrimitiveType _) = Refl
fromToSum (Spelt _) = Refl
fromToSum (Character _) = Refl

export
DecEq Form where
  decEq f g = case decEq (toSum f) (toSum g) of
    Yes eq => Yes (trans (sym (fromToSum f)) (trans (cong fromSum eq) (fromToSum g)))
    No ne => No (\eq => ne (cong toSum eq))

||| A form by its numbers: its kind, then its parts', which tells forms
||| apart and orders them.
export
formCode : Form -> List Nat
formCode (Shaped s) = [0, finToNat (shapeCode s)]
formCode (Bound b q p) = [1, finToNat (bindingCode b), finToNat q, finToNat (passingCode p)]
formCode (IntegerLit t negative) = [2, finToNat t, if negative then 1 else 0]
formCode (PrimitiveType t) = [3, finToNat t]
formCode (Spelt (h, l)) = [4, finToNat h, finToNat l]
formCode (Character (h, l)) = [5, finToNat h, finToNat l]

export
Eq Form where
  f == g = formCode f == formCode g

export
Ord Form where
  compare f g = compare (formCode f) (formCode g)

bools : Listed Bool
bools = MkListed [False, True] (\case False => Here; True => There Here)

glyphs : Listed Glyph
glyphs = listedPair (listedFin 1088) (listedFin 1024)

sums : Listed Sum
sums =
  listedEither (listedNumbered shapes)
    (listedEither (listedPair (listedNumbered bindings) (listedPair (listedFin 3) (listedNumbered passings)))
       (listedEither (listedPair (listedFin 14) bools)
          (listedEither (listedFin 14) (listedEither glyphs glyphs))))

||| Every form, listed.
export
forms : Listed Form
forms = listedVia toSum fromSum fromToSum sums

||| A form as text that tells forms apart and reads the same in every build.
export
formText : Form -> String
formText f = concatMap (\n => show n ++ ".") (formCode f)
