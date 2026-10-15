-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What the registry's hooks make of a definition's calls.
module IdrisMLIR.Frontend.Translate.Hooks

import IdrisMLIR.Dialect.Idr
import IdrisMLIR.MLIR
import IdrisMLIR.Registry
import IdrisMLIR.Types

import Data.Maybe

%default covering

||| The first hook that yields a value. Every reader of a hook asks this,
||| so a new hook is one case here and nowhere else a list is walked.
firstOf : (Hook -> Maybe a) -> List Hook -> Maybe a
firstOf _ [] = Nothing
firstOf f (h :: hs) = case f h of
  Just x => Just x
  Nothing => firstOf f hs

||| Is a definition the identity on its last argument?
export
identityOnLast : List Hook -> Bool
identityOnLast = isJust . firstOf (\h => case h of
  IdentityOnLastArgument => Just ()
  _ => Nothing)

||| The primitive a definition's calls are, and the literal operands that
||| follow the call's own.
export
ioCallOf : List Hook -> Maybe (IdrPrim, List Lit)
ioCallOf = firstOf (\h => case h of
  IOCall p lits => Just (p, lits)
  _ => Nothing)

||| The array primitive a definition's calls are.
export
arrayCallOf : List Hook -> Maybe IdrPrim
arrayCallOf = firstOf (\h => case h of
  ArrayCall p => Just p
  _ => Nothing)

||| The dimensions and the element of an external type that is an array a
||| world orders: the element `Nothing` when its type argument names it,
||| `Just` a fixed one.
export
orderedArrayOf : List Hook -> Maybe (List Dim, Maybe Ty)
orderedArrayOf = firstOf (\h => case h of
  OrderedArrayType ds e => Just (ds, e)
  _ => Nothing)

||| Is a type constructor a value of the array language, a tensor?
export
isValueArray : List Hook -> Bool
isValueArray = isJust . firstOf (\h => case h of
  ArrayValueType => Just ()
  _ => Nothing)

||| The operation of the array language a definition's calls are, if any.
export
generatingOf : List Hook -> Maybe ArrayPrim
generatingOf = firstOf (\h => case h of
  Generating p => Just p
  _ => Nothing)

||| The part a constructor plays, if the registry names one.
export
roleOf : List Hook -> Maybe Role
roleOf = firstOf (\h => case h of
  Plays r => Just r
  _ => Nothing)

||| The promise a data type's values keep, if the registry names one.
export
promiseOf : List Hook -> Maybe Promise
promiseOf = firstOf (\h => case h of
  Promises p => Just p
  _ => Nothing)

||| The primitive that builds the string a definition's calls build from
||| their list, if the registry says they build one.
export
builderOf : List Hook -> Maybe IdrPrim
builderOf = firstOf (\h => case h of
  Builds p => Just p
  _ => Nothing)

||| Is a type constructor the external type that is a machine word?
export
isWordType : List Hook -> Bool
isWordType = isJust . firstOf (\h => case h of
  WordType => Just ()
  _ => Nothing)

||| What a function on naturals means, if it is one the registry knows.
export
natOperationOf : List Hook -> Maybe NatMeaning
natOperationOf = firstOf (\h => case h of
  NatOperation m => Just m
  _ => Nothing)

||| The primitive that ends the program, if a definition's calls do.
export
exitOf : List Hook -> Maybe IdrPrim
exitOf = firstOf (\h => case h of
  Exits p => Just p
  _ => Nothing)

||| The string of `System.Info` a definition is, if the registry knows it.
export
systemFactOf : List Hook -> Maybe SystemFact
systemFactOf = firstOf (\h => case h of
  SystemInfo f => Just f
  _ => Nothing)

||| The replacement a deprecated name names, if the registry rejects it.
export
deprecatedOf : List Hook -> Maybe String
deprecatedOf = firstOf (\h => case h of
  Deprecated replacement => Just replacement
  _ => Nothing)

||| Whether a definition is a trusted library's crash of a string.
export
libraryCrashOf : List Hook -> Bool
libraryCrashOf = isJust . firstOf (\h => case h of
  LibraryCrash => Just ()
  _ => Nothing)
