-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
||| A payload with metadata attached: its location, its name, its quantity,
||| its documentation and the like.
|||
||| Each combination of metadata that is used is a record of its own, every
||| field of it at a fixed type, so what a value holds is what its record
||| states: no type is held when the checker runs, no field's type is
||| computed, and no field is found by its label. Idris makes each record's
||| projections (`.fc`, `.name`, `.rig`, `.val`, ...) in the record's own
||| namespace, so a projection resolves by the record it is applied to.
||| A combination is named by its fields in order, the order a TTC writes
||| them in (`Core.TTC`).
module Core.WithData

import Core.TT
import Libraries.Text.Bounded

export infixr 9 :+

------------------------------------------------------------------------------------------
-- The combinations of metadata
------------------------------------------------------------------------------------------

||| A payload with its location. The constructor is the one the reflected
||| `WithFC` has, so the checker and the reflected syntax name it alike.
public export
record WithFC a where
  constructor MkFCVal
  fc : FC
  val : a

||| A payload with a name (a binder, a record's header).
public export
record WithName a where
  constructor MkWithName
  name : WithFC Name
  val : a

||| A payload with its location and a type's name (a type declaration).
public export
record WithFCTyName a where
  constructor MkWithFCTyName
  fc : FC
  tyName : WithFC Name
  val : a

||| A payload with its location, a name and an arity (a type or data constructor).
public export
record WithFCNameArity a where
  constructor MkWithFCNameArity
  fc : FC
  name : WithFC Name
  arity : Nat
  val : a

||| A payload with a quantity and a name (a parameter).
public export
record WithRigName a where
  constructor MkWithRigName
  rig : RigCount
  name : WithFC Name
  val : a

||| A payload with its location, a quantity and a name (a field, an implicit).
public export
record WithFCRigName a where
  constructor MkWithFCRigName
  fc : FC
  rig : RigCount
  name : WithFC Name
  val : a

||| A payload with a name and data options (a record's body).
public export
record WithNameOpts a where
  constructor MkWithNameOpts
  name : WithFC Name
  opts : List DataOpt
  val : a

||| A payload with a quantity and perhaps a name (a binder read back from a type).
public export
record WithRigMName a where
  constructor MkWithRigMName
  rig : RigCount
  mName : Maybe (WithFC Name)
  val : a

||| A payload with its location, a quantity and perhaps a name (a binder of a
||| constructor's type).
public export
record WithFCRigMName a where
  constructor MkWithFCRigMName
  fc : FC
  rig : RigCount
  mName : Maybe (WithFC Name)
  val : a

||| A payload with documentation and its location (a constructor's name).
public export
record WithDocFC a where
  constructor MkWithDocFC
  doc : String
  fc : FC
  val : a

||| A payload with its location, documentation, a quantity and names (a
||| record's field).
public export
record WithFCDocRigNames a where
  constructor MkWithFCDocRigNames
  fc : FC
  doc : String
  rig : RigCount
  names : List (WithFC Name)
  val : a

||| A payload with a name, a quantity and a totality requirement (an
||| interface's method).
public export
record WithNameRigTot a where
  constructor MkWithNameRigTot
  name : WithFC Name
  rig : RigCount
  totReq : Maybe TotalReq
  val : a

------------------------------------------------------------------------------------------
-- Each combination is functorial in its payload only
------------------------------------------------------------------------------------------

export
Functor WithFC where
  map f (MkFCVal fc x) = MkFCVal fc (f x)

export
Functor WithName where
  map f (MkWithName n x) = MkWithName n (f x)

export
Functor WithFCTyName where
  map f (MkWithFCTyName fc n x) = MkWithFCTyName fc n (f x)

export
Functor WithFCNameArity where
  map f (MkWithFCNameArity fc n a x) = MkWithFCNameArity fc n a (f x)

export
Functor WithRigName where
  map f (MkWithRigName r n x) = MkWithRigName r n (f x)

export
Functor WithFCRigName where
  map f (MkWithFCRigName fc r n x) = MkWithFCRigName fc r n (f x)

export
Functor WithNameOpts where
  map f (MkWithNameOpts n o x) = MkWithNameOpts n o (f x)

export
Functor WithRigMName where
  map f (MkWithRigMName r n x) = MkWithRigMName r n (f x)

export
Functor WithFCRigMName where
  map f (MkWithFCRigMName fc r n x) = MkWithFCRigMName fc r n (f x)

export
Functor WithDocFC where
  map f (MkWithDocFC d fc x) = MkWithDocFC d fc (f x)

export
Functor WithFCDocRigNames where
  map f (MkWithFCDocRigNames fc d r ns x) = MkWithFCDocRigNames fc d r ns (f x)

export
Functor WithNameRigTot where
  map f (MkWithNameRigTot n r t x) = MkWithNameRigTot n r t (f x)

------------------------------------------------------------------------------------------
-- Location
------------------------------------------------------------------------------------------

export
setFC : FC -> WithFC a -> WithFC a
setFC fc' = { fc := fc' }

||| A payload with no location.
%inline export
NoFC : a -> WithFC a
NoFC = MkFCVal EmptyFC

export
(.withFC) : (o : OriginDesc) => WithBounds t -> WithFC t
x.withFC = MkFCVal x.toFC x.val

------------------------------------------------------------------------------------------
-- Names
------------------------------------------------------------------------------------------

namespace WithFCRigName
  ||| The name, without its location.
  export
  (.nameVal) : WithFCRigName a -> Name
  (.nameVal) x = x.name.val

namespace WithNameRigTot
  ||| The name, without its location.
  export
  (.nameVal) : WithNameRigTot a -> Name
  (.nameVal) x = x.name.val

------------------------------------------------------------------------------------------
-- Documentation
------------------------------------------------------------------------------------------

||| Documentation added to a located payload.
export
(:+) : String -> WithFC a -> WithDocFC a
doc :+ MkFCVal fc x = MkWithDocFC doc fc x

||| A located payload with no documentation.
export
undocumented : WithFC a -> WithDocFC a
undocumented x = "" :+ x

------------------------------------------------------------------------------------------
-- Distribution over List
------------------------------------------------------------------------------------------

export
distribData : WithFC (List a) -> List (WithFC a)
distribData x = map (MkFCVal x.fc) x.val

------------------------------------------------------------------------------------------
-- Equality: the payload, then the location
------------------------------------------------------------------------------------------

export
Eq a => Eq (WithFC a) where
  x == y = x.val == y.val && x.fc == y.fc
