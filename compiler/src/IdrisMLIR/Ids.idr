||| Identifiers. Each kind of name is its own type, so a function name cannot
||| be used where a data type is meant.
module IdrisMLIR.Ids

%default total

||| A function instance.
public export
record FnId where
  constructor MkFnId
  name : String

||| A monomorphic data instance, named `<Idris name>[<type arguments>]`.
public export
record DataId where
  constructor MkDataId
  name : String

||| A constructor of a data instance: the instance and the Idris full name.
public export
record ConId where
  constructor MkConId
  dataId : DataId
  name : String

||| An Idris name as it is printed: what the compiler reports, never what it
||| compares. It has `Show` and no `Eq`, so code outside the registry can
||| name a definition in a message but cannot key behaviour on it.
export
data Shown = MkShown String

export
shown : String -> Shown
shown = MkShown

export
Show Shown where
  show (MkShown s) = s

||| What a function or data instance is an instance of: the definition and
||| the compile-time values it was instantiated at, each the
||| alpha-normalized text the frontend prints. Emit writes it as
||| #idr.instance and derives the symbol's readable name from it; nothing
||| else reads the name.
public export
record InstanceKey where
  constructor MkInstanceKey
  origin : String            -- the definition's printed full name
  arguments : List String    -- each compile-time argument, alpha-normalized text

export Eq FnId where a == b = a.name == b.name
export Ord FnId where compare a b = compare a.name b.name
export Show FnId where show = (.name)

export Eq DataId where a == b = a.name == b.name
export Ord DataId where compare a b = compare a.name b.name
export Show DataId where show = (.name)

export Eq ConId where a == b = a.dataId == b.dataId && a.name == b.name
export Ord ConId where compare a b = compare (a.dataId, a.name) (b.dataId, b.name)
export Show ConId where show c = c.name
