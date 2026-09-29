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
