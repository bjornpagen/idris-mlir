||| The notation of linear programs: linear implication and the
||| unrestricted modality, spelled as upstream's `Data.Linear.Notation`
||| spells them, so that a program reads the same over either.
module Linear.Notation

%default total

export infixr 0 -@
||| Infix notation for linear implication.
public export
(-@) : Type -> Type -> Type
a -@ b = (1 _ : a) -> b

||| The linear identity function.
public export
id : a -@ a
id x = x

||| Linear function composition.
public export
(.) : (b -@ c) -@ (a -@ b) -@ (a -@ c)
(.) f g v = f (g v)

export prefix 5 !*
||| Prefix notation for the linear unrestricted modality: a value a linear
||| context may use any number of times, or give out of a linear scope.
public export
data (!*) : Type -> Type where
  MkBang : a -> !* a

||| Unpack an unrestricted value in a linear context.
public export
unrestricted : !* a -@ a
unrestricted (MkBang unr) = unr

||| Unpack an unrestricted value in a linear context, as a postfix.
public export
(.unrestricted) : !* a -@ a
(.unrestricted) = unrestricted
