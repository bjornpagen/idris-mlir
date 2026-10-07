||| What the registry's hooks make of a definition's calls.
module IdrisMLIR.Frontend.Translate.Hooks

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

||| The IO operation a definition's calls are.
export
ioCallOf : List Hook -> Maybe IOOp
ioCallOf = firstOf (\h => case h of
  IOCall op => Just op
  _ => Nothing)

||| The array operation a definition's calls are.
export
arrayCallOf : List Hook -> Maybe ArrayOp
arrayCallOf = firstOf (\h => case h of
  ArrayCall op => Just op
  _ => Nothing)

||| The element of an external type that is an array: `Nothing` when its
||| type argument names it, `Just` a fixed one.
export
arrayElementOf : List Hook -> Maybe (Maybe Ty)
arrayElementOf = firstOf (\h => case h of
  ArrayType e => Just e
  _ => Nothing)

||| The string a definition's calls build from their list, if the registry
||| says they build one.
export
builderOf : List Hook -> Maybe Builder
builderOf = firstOf (\h => case h of
  Builds b => Just b
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

||| The loop over an array's index space a definition is, if the registry
||| knows it as one.
export
arrayLoopOf : List Hook -> Maybe ArrayLoop
arrayLoopOf = firstOf (\h => case h of
  ArrayLoop l => Just l
  _ => Nothing)
