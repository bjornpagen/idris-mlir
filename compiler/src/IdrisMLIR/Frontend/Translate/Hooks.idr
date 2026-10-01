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

||| Is a type constructor the external type of arrays?
export
isArrayType : List Hook -> Bool
isArrayType [] = False
isArrayType (ArrayType :: _) = True
isArrayType (_ :: hs) = isArrayType hs

||| What a function on naturals means, if it is one the registry knows.
export
natOperationOf : List Hook -> Maybe NatMeaning
natOperationOf [] = Nothing
natOperationOf (NatOperation m :: _) = Just m
natOperationOf (_ :: hs) = natOperationOf hs
