||| Identifiers. Each kind of name is its own type, so a function name cannot
||| be used where a data type is meant.
module IdrisMLIR.Ids

%default total

||| A function instance or specialization (ELIM-MONO-4, ELIM-G-3).
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

||| A variable of first-order Core: unique within its function (CORE-INV-1).
public export
record VarId where
  constructor MkVarId
  index : Nat

||| A join point of first-order Core: unique within its function.
public export
record JoinId where
  constructor MkJoinId
  index : Nat

||| The program point of a lambda or `Delay` in full Core: the identity of a
||| closure, and of its specializations (ELIM-G-3).
public export
record Label where
  constructor MkLabel
  index : Nat

||| An Idris name as it is printed: what the compiler reports, never what it
||| compares. It has `Show` and no `Eq`, so code outside the registry can
||| name a definition in a message but cannot key behaviour on it
||| (docs/architecture/17-registry.md).
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

export Eq VarId where a == b = a.index == b.index
export Ord VarId where compare a b = compare a.index b.index
export Show VarId where show v = "%" ++ show v.index

export Eq JoinId where a == b = a.index == b.index
export Ord JoinId where compare a b = compare a.index b.index
export Show JoinId where show j = "j" ++ show j.index

export Eq Label where a == b = a.index == b.index
export Ord Label where compare a b = compare a.index b.index
export Show Label where show l = "lam" ++ show l.index
