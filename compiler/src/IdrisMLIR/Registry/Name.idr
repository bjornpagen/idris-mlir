||| Qualified Idris names as the registry writes them
||| (docs/architecture/17-registry.md). Values of `QName` are written only in
||| the registry: the frontend turns Idris's names into them to ask it, and
||| the registry does every comparison.
module IdrisMLIR.Registry.Name

import Data.String

%default total

||| An Idris name in a namespace: `Prelude.IO.prim__putStr` is
||| `MkQName ["Prelude", "IO"] "prim__putStr"`.
public export
record QName where
  constructor MkQName
  ||| The namespace, outermost first; empty for a primitive.
  space : List String
  name : String

export
Eq QName where
  a == b = a.name == b.name && a.space == b.space

export
Show QName where
  show q = concatMap (++ ".") q.space ++ q.name
