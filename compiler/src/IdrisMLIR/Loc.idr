||| Source locations, kept independent of Idris's `FC` so that the middle end
||| does not import the Idris compiler (FE-IN-3).
module IdrisMLIR.Loc

%default total

||| Where a source file came from, so the frontend can rebuild Idris's `FC`.
public export
data Origin = FromModule (List String) | FromPackage String | Nowhere

||| A source span, 0-based as in Idris.
public export
record Loc where
  constructor MkLoc
  origin : Origin
  file : String
  startLine : Int
  startCol : Int
  endLine : Int
  endCol : Int

export
noLoc : Loc
noLoc = MkLoc Nowhere "" 0 0 0 0

||| `file:line:column`, 1-based, for messages; a library module whose
||| source is not installed is named by its module.
export
Show Loc where
  show l = where_ ++ ":" ++ show (l.startLine + 1) ++ ":" ++ show (l.startCol + 1)
    where
      dotted : List String -> String
      dotted [] = ""
      dotted [x] = x
      dotted (x :: xs) = x ++ "." ++ dotted xs
      where_ : String
      where_ = case (l.file, l.origin) of
        ("", FromModule ns) => dotted (reverse ns)
        (f, _) => f

||| Is a location in one of the libraries the compiler trusts (the Prelude,
||| `Builtin`, `PrimIO`, `IdrisMLIR.IO`)? A diagnostic there is reported at
||| the user's code that reached it (DIAG-LOC-1).
export
inLibrary : Loc -> Bool
inLibrary l = case l.origin of
  FromModule ns => any trusted [dotted ns, dotted (reverse ns)]
  FromPackage _ => True
  Nowhere => False
  where
    dotted : List String -> String
    dotted [] = ""
    dotted [x] = x
    dotted (x :: xs) = x ++ "." ++ dotted xs
    trusted : String -> Bool
    trusted m = any (\t => m == t || substr 0 (length t + 1) m == t ++ ".")
                    ["Builtin", "PrimIO", "Prelude", "IdrisMLIR.IO"]

||| Is a location known at all?
export
known : Loc -> Bool
known l = case l.origin of
  Nowhere => False
  _ => True
