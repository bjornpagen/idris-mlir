||| A payload with metadata attached: its location, its name, its quantity,
||| its documentation and the like.
|||
||| Upstream builds these from one extensible record, `WithData fields a`,
||| whose `fields` is a list of labels and types, each value's type computed
||| from that list. Here each combination of metadata that is used is a
||| record of its own, and every field has a fixed type. The fields keep
||| upstream's projection names (`.fc`, `.val`, `.name`, `.rig`, ...), which
||| resolve by the type of the record, as upstream's did by its field list.
||| A combination is named by its fields in order; that order is the order
||| upstream's metadata list had, which a TTC writes them in.
module Core.WithData

import Core.TT
import Libraries.Text.Bounded

export infixr 9 :+

------------------------------------------------------------------------------------------
-- The combinations of metadata
------------------------------------------------------------------------------------------

||| A payload with its location.
||| The constructor keeps upstream's name, which call sites match on.
public export
record WithFC a where
  constructor MkWithData
  fc : FC
  val : a

||| A payload with a name.
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

||| A payload with a quantity and perhaps a name (a binder).
public export
record WithRigMName a where
  constructor MkWithRigMName
  rig : RigCount
  mName : Maybe (WithFC Name)
  val : a

||| A payload with its location, a quantity and perhaps a name.
public export
record WithFCRigMName a where
  constructor MkWithFCRigMName
  fc : FC
  rig : RigCount
  mName : Maybe (WithFC Name)
  val : a

||| A payload with documentation and its location (a record's constructor).
public export
record WithDocFC a where
  constructor MkWithDocFC
  doc : String
  fc : FC
  val : a

||| A payload with documentation, a quantity and names (a record's field).
public export
record WithDocRigNames a where
  constructor MkWithDocRigNames
  doc : String
  rig : RigCount
  names : List (WithFC Name)
  val : a

||| A payload with its location, documentation, a quantity and names.
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
  map f (MkWithData fc x) = MkWithData fc (f x)

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
Functor WithDocRigNames where
  map f (MkWithDocRigNames d r ns x) = MkWithDocRigNames d r ns (f x)

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

||| A wrapper for a value with a file context.
public export
MkFCVal : FC -> ty -> WithFC ty
MkFCVal = MkWithData

||| Smart constructor for WithFC that uses EmptyFC as location
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
  ||| Extract the name out of the metadata.
  export
  (.nameVal) : WithFCRigName a -> Name
  (.nameVal) x = x.name.val

namespace WithNameRigTot
  ||| Extract the name out of the metadata.
  export
  (.nameVal) : WithNameRigTot a -> Name
  (.nameVal) x = x.name.val

------------------------------------------------------------------------------------------
-- Adding metadata
------------------------------------------------------------------------------------------

namespace DocFC
  ||| Add documentation to a located payload.
  export
  (:+) : String -> WithFC a -> WithDocFC a
  doc :+ MkWithData fc x = MkWithDocFC doc fc x

namespace FCRigName
  ||| Add a location to a parameter.
  export
  (:+) : FC -> WithRigName a -> WithFCRigName a
  fc :+ MkWithRigName rig n x = MkWithFCRigName fc rig n x

namespace FCDocRigNames
  ||| Add a location to a record's field.
  export
  (:+) : FC -> WithDocRigNames a -> WithFCDocRigNames a
  fc :+ MkWithDocRigNames doc rig ns x = MkWithFCDocRigNames fc doc rig ns x

||| Add a location to a record's field, from its bounds.
export
(.addFC) : (o : OriginDesc) => WithBounds (WithDocRigNames t) -> WithFCDocRigNames t
(.addFC) x = x.toFC :+ x.val

||| Add the default documentation, none, to a located payload.
export
AddDef : WithFC a -> WithDocFC a
AddDef x = "" :+ x

------------------------------------------------------------------------------------------
-- Distribution over List
------------------------------------------------------------------------------------------

export
distribData : WithFC (List a) -> List (WithFC a)
distribData x = map (MkWithData x.fc) x.val

------------------------------------------------------------------------------------------
-- Equality: the payload, then the metadata
------------------------------------------------------------------------------------------

export
Eq a => Eq (WithFC a) where
  x == y = x.val == y.val && x.fc == y.fc
