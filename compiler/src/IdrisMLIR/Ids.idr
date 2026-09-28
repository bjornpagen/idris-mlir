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

||| The program point of a lambda or `Delay` in full Core: the identity of a
||| closure, and of the function lifted from it.
public export
record Label where
  constructor MkLabel
  index : Nat

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

export Eq FnId where a == b = a.name == b.name
export Ord FnId where compare a b = compare a.name b.name
export Show FnId where show = (.name)

export Eq DataId where a == b = a.name == b.name
export Ord DataId where compare a b = compare a.name b.name
export Show DataId where show = (.name)

export Eq ConId where a == b = a.dataId == b.dataId && a.name == b.name
export Ord ConId where compare a b = compare (a.dataId, a.name) (b.dataId, b.name)
export Show ConId where show c = c.name

export Eq Label where a == b = a.index == b.index
export Ord Label where compare a b = compare a.index b.index
export Show Label where show l = "lam" ++ show l.index
