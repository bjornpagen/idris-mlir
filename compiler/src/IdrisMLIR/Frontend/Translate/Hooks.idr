||| What the registry's hooks make of a definition's calls.
module IdrisMLIR.Frontend.Translate.Hooks

import IdrisMLIR.Registry
import IdrisMLIR.Types

%default covering

||| Is a definition the identity on its last argument?
export
identityOnLast : List Hook -> Bool
identityOnLast [] = False
identityOnLast (IdentityOnLastArgument :: _) = True
identityOnLast (_ :: hs) = identityOnLast hs

||| The IO operation a definition's calls are.
export
ioCallOf : List Hook -> Maybe IOOp
ioCallOf [] = Nothing
ioCallOf (IOCall op :: _) = Just op
ioCallOf (_ :: hs) = ioCallOf hs

||| The array operation a definition's calls are.
export
arrayCallOf : List Hook -> Maybe ArrayOp
arrayCallOf [] = Nothing
arrayCallOf (ArrayCall op :: _) = Just op
arrayCallOf (_ :: hs) = arrayCallOf hs

||| The element of an external type that is an array: `Nothing` when its
||| type argument names it, `Just` a fixed one.
export
arrayElementOf : List Hook -> Maybe (Maybe Ty)
arrayElementOf [] = Nothing
arrayElementOf (ArrayType e :: _) = Just e
arrayElementOf (_ :: hs) = arrayElementOf hs

||| The string a definition's calls build from their list, if the registry
||| says they build one.
export
builderOf : List Hook -> Maybe Builder
builderOf [] = Nothing
builderOf (Builds b :: _) = Just b
builderOf (_ :: hs) = builderOf hs

||| Is a type constructor the external type that is a machine word?
export
isWordType : List Hook -> Bool
isWordType [] = False
isWordType (WordType :: _) = True
isWordType (_ :: hs) = isWordType hs

||| What a function on naturals means, if it is one the registry knows.
export
natOperationOf : List Hook -> Maybe NatMeaning
natOperationOf [] = Nothing
natOperationOf (NatOperation m :: _) = Just m
natOperationOf (_ :: hs) = natOperationOf hs

||| The loop over an array's index space a definition is, if the registry
||| knows it as one.
export
arrayLoopOf : List Hook -> Maybe ArrayLoop
arrayLoopOf [] = Nothing
arrayLoopOf (ArrayLoop l :: _) = Just l
arrayLoopOf (_ :: hs) = arrayLoopOf hs
