-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Libraries.Utils.Path

import Data.List
import Data.List1
import Data.Maybe
import Data.Nat
import Data.String
import Libraries.Utils.String

import Libraries.Data.String.Extra

%default total

export infixl 5 </>, />
export infixr 7 <.>
export infixr 7 <..>

-- Every target this compiler runs on and builds for reads a path with one
-- grammar: a name is any bytes but '/' and NUL, and '/' alone separates.
-- Upstream read every path with Windows's grammar too, on every platform,
-- asking the host's operating system at run time where it differed: a
-- backslash separated, a leading `x:` was a disk and a ':' or '?' ended the
-- path, so `/tmp/a:b` was read as `/tmp/a`. Here ':', '?' and '\\' are
-- ordinary characters of a name.

||| A single body in path.
public export
data Body
  =
  ||| Represents ".".
  CurDir |
  ||| Represents "..".
  ParentDir |
  ||| Directory or file.
  Normal String

||| A parsed file system path: an optional root and the names after it.
|||
||| Use the function `parse` to constructs a Path from String, and use the
||| function `show` to convert in reverse.
|||
||| Trailing separator is only used for display and is ignored when comparing
||| paths.
public export
record Path where
    constructor MkPath
    ||| Whether the path contains root.
    hasRoot : Bool
    ||| Path bodies.
    body : List Body
    ||| Whether the path terminates with a separator.
    hasTrailSep : Bool

export
Eq Body where
  (==) CurDir CurDir = True
  (==) ParentDir ParentDir = True
  (==) (Normal l) (Normal r) = l == r
  (==) _ _ = False

export
Eq Path where
  (==) (MkPath l1 l2 _) (MkPath r1 r2 _) =
    l1 == r1 && l2 == r2

||| An empty path, which represents "".
public export
emptyPath : Path
emptyPath = MkPath False [] False

--------------------------------------------------------------------------------
-- Show
--------------------------------------------------------------------------------

export
Show Body where
  show CurDir = "."
  show ParentDir = ".."
  show (Normal normal) = normal

||| Displays the path, its names separated by '/'.
export
Show Path where
  show path =
    let
      showRoot = if path.hasRoot then "/" else ""
      showBody = join "/" $ map show path.body
      showTrail = if path.hasTrailSep then "/" else ""
    in
      showRoot ++ showBody ++ showTrail

--------------------------------------------------------------------------------
-- Parser
--------------------------------------------------------------------------------

-- Paths are parsed by hand, in one pass over their characters: every search
-- for a module's TTC parses some fifty, so a lexer and a grammar built from
-- combinators, which upstream used, were a tenth of elaboration.

-- A path's tokens: each '/' alone, and each run of the other characters.
data PathToken = Separator | Text String

lexPath : String -> List PathToken
lexPath str = lexFrom [] [] (unpack str)
  where
    -- the text being read, its characters last first, ended before `acc`,
    -- the tokens read before it, last first
    ended : List Char -> List PathToken -> List PathToken
    ended [] acc = acc
    ended run acc = Text (pack (reverse run)) :: acc

    lexFrom : List PathToken -> List Char -> List Char -> List PathToken
    lexFrom acc run [] = reverse (ended run acc)
    lexFrom acc run (c :: cs)
        = if c == '/'
             then lexFrom (Separator :: ended run acc) [] cs
             else lexFrom acc (c :: run) cs

parseBody : String -> Body
parseBody ".." = ParentDir
parseBody "." = CurDir
parseBody normal = Normal normal

-- The names that follow the root, each run of separators between two names
-- one separator. With whether separators follow the last name.
parseBodies : List PathToken -> (List Body, Bool)
parseBodies = bodiesFrom [] False
  where
    bodiesFrom : List Body -> (trailSep : Bool) -> List PathToken -> (List Body, Bool)
    bodiesFrom acc trailSep (Text text :: ts) = bodiesFrom (parseBody text :: acc) False ts
    bodiesFrom acc trailSep (Separator :: ts) = bodiesFrom acc True ts
    bodiesFrom acc trailSep [] = (reverse acc, trailSep)

-- Whether the path starts at the root, and the tokens after its leading
-- separators.
parseRoot : List PathToken -> (Bool, List PathToken)
parseRoot (Separator :: ts) = (True, dropSeparators ts)
  where
    dropSeparators : List PathToken -> List PathToken
    dropSeparators (Separator :: rest) = dropSeparators rest
    dropSeparators rest = rest
parseRoot ts = (False, ts)

||| Parses a String into Path.
|||
||| - Only '/' separates; every other character, ':', '?' and '\\' among
|||   them, is part of a name, and any characters in a name are allowed,
|||   e.g., glob like "/root/*";
||| - Repeated separators are ignored, therefore, "a/b" and "a//b" both have "a"
|||   and "b" as bodies.
||| - "." in the body are removed, unless they are at the beginning of the path.
|||   For example, "a/./b", "a/b/", "a/b/." and "a/b" will have "a" and "b" as
|||   bodies, and "./a/b" will starts with `CurDir`.
|||
||| ```idris example
||| parse "/usr/local/etc/*"
||| ```
export
parse : String -> Path
parse str =
  let (root, ts) = parseRoot (lexPath str)
      (body, trailSep) = parseBodies ts
      body = filter (\case Normal s => trimStart s /= ""; _ => True) body
      body = case body of
               [] => []
               (x::xs) => x :: delete CurDir xs
  in MkPath root body trailSep

--------------------------------------------------------------------------------
-- Utils
--------------------------------------------------------------------------------

append' : (left : Path) -> (right : Path) -> Path
append' left right =
  if right.hasRoot then
    right
  else
    { body := left.body ++ right.body, hasTrailSep := right.hasTrailSep } left

splitPath' : Path -> List Path
splitPath' path =
  if path.hasRoot
     then MkPath True [] False :: iterateBody (path.body) (path.hasTrailSep)
     else iterateBody (path.body) (path.hasTrailSep)
  where
    iterateBody : List Body -> (trailSep : Bool) -> List Path
    iterateBody [] _ = []
    iterateBody [x] trailSep = [MkPath False [x] trailSep]
    iterateBody (x::y::xs) trailSep =
      (MkPath False [x] False) :: iterateBody (y::xs) trailSep

splitParent' : Path -> Maybe (Path, Path)
splitParent' path =
  case path.body of
    [] => Nothing
    (x::xs) =>
      let
        parent = { body := init (x::xs), hasTrailSep := False } path
        child = MkPath False [last (x::xs)] path.hasTrailSep
      in
        Just (parent, child)

parent' : Path -> Maybe Path
parent' = map fst . splitParent'

fileName' : Path -> Maybe String
fileName' path =
  findNormal $ reverse path.body
where
  findNormal : List Body -> Maybe String
  findNormal ((Normal normal)::xs) = Just normal
  findNormal (CurDir::xs) = findNormal xs
  findNormal _ = Nothing

setFileName' : (name : String) -> Path -> Path
setFileName' name path =
  if isJust (fileName' path) then
    append' (fromMaybe emptyPath $ parent' path) (parse name)
  else
    append' path (parse name)

export
splitFileName : String -> (String, String)
splitFileName name =
  case break (== '.') $ reverse $ unpack name of
    (_, []) => (name, "")
    (_, ['.']) => (name, "")
    (revExt, (dot :: revStem)) =>
      ((pack $ reverse revStem), (pack $ reverse revExt))

||| Split a file name into a basename and a list of extensions.
||| A leading dot is considered to be part of the basename.
||| ```
||| splitExtensions "Path.idr"           = ("Path", ["idr"])
||| splitExtensions "file.latex.lidr"    = ("file", ["latex", "lidr"])
||| splitExtensions ".hidden.latex.lidr" = (".hidden", ["latex", "lidr"])
||| ```
export
splitExtensions : String -> (String, List String)
splitExtensions name = case map pack $ split (== '.') (unpack name) of
  ("" ::: base :: exts) => ("." ++ base, exts)
  (base ::: exts) => (base, exts)

--------------------------------------------------------------------------------
-- Methods
--------------------------------------------------------------------------------

||| Returns true if the path is absolute: it starts with the root.
export
isAbsolute : String -> Bool
isAbsolute = hasRoot . parse

||| Returns true if the path is relative.
export
isRelative : String -> Bool
isRelative = not . isAbsolute

||| Appends the right path to the left path.
|||
||| If the path on the right is absolute, it replaces the left path.
|||
||| ```idris example
||| parse "/usr" /> "local/etc" == "/usr/local/etc"
||| ```
export
(/>) : (left : Path) -> (right : String) -> Path
(/>) left right = append' left (parse right)

||| Appends the right path to the left path.
|||
||| If the path on the right is absolute, it replaces the left path.
|||
||| ```idris example
||| "/usr" </> "local/etc" == "/usr/local/etc"
||| ```
export
(</>) : (left : String) -> (right : String) -> String
(</>) left right = show $ parse left /> right


||| Joins path components into one.
|||
||| ```idris example
||| joinPath ["/usr", "local/etc"] == "/usr/local/etc"
||| ```
export
joinPath : List String -> String
joinPath xs = show $ foldl (/>) (parse "") xs

||| Splits path into components.
|||
||| ```idris example
||| splitPath "/usr/local/etc" == ["/", "usr", "local", "etc"]
||| splitPath "tmp/Foo.idr" == ["tmp", "Foo.idr"]
||| ```
export
splitPath : String -> List String
splitPath = map show . splitPath' . parse

||| Splits the path into parent and child.
|||
||| ```idris example
||| splitParent "/usr/local/etc" == Just ("/usr/local", "etc")
||| ```
export
splitParent : String -> Maybe (String, String)
splitParent path =
  do
    (parent, child) <- splitParent' (parse path)
    pure (show parent, show child)

||| Returns the path without its final component, if there is one.
|||
||| Returns Nothing if the path terminates by a root.
export
parent : String -> Maybe String
parent = map show . parent' . parse

||| Returns the list of all parents of the path, longest first, self included.
|||
||| ```idris example
||| parents "/etc/kernel" == ["/etc/kernel", "/etc", "/"]
||| ```
export
covering
parents : String -> List String
parents = map show . List.iterate parent' . parse

||| Determines whether the base is one of the parents of target.
|||
||| Trailing separator is ignored.
|||
||| ```idris example
||| "/etc" `isBaseOf` "/etc/kernel"
||| ```
export
isBaseOf : (base : String) -> (target : String) -> Bool
isBaseOf base target =
  let
    MkPath baseRoot baseBody _ = parse base
    MkPath targetRoot targetBody _ = parse target
  in
       baseRoot == targetRoot
    && (baseBody `isPrefixOf` targetBody)

||| Returns a path that, when appended to base, yields target.
|||
||| Returns Nothing if the base is not a prefix of the target.
export
dropBase : (base : String) -> (target : String) -> Maybe String
dropBase base target =
  do
    let MkPath baseRoot baseBody _ = parse base
    let MkPath targetRoot targetBody targetTrialSep = parse target
    if baseRoot == targetRoot then Just () else Nothing
    body <- dropBody baseBody targetBody
    pure $ show $ MkPath False body targetTrialSep
  where
    dropBody : (base : List Body) -> (target : List Body) -> Maybe (List Body)
    dropBody [] ys = Just ys
    dropBody xs [] = Nothing
    dropBody (x::xs) (y::ys) = if x == y then dropBody xs ys else Nothing

||| Returns the last body of the path.
|||
||| If the last body is a file, this is the file name;
||| if it's a directory, this is the directory name;
||| if it's ".", it recurses on the previous body;
||| if it's "..", returns Nothing.
export
fileName : String -> Maybe String
fileName  = fileName' . parse

||| Extracts the file name in the path without extension.
|||
||| The stem is:
|||
||| - Nothing, if there is no file name;
||| - The entire file name if there is no embedded ".";
||| - The entire file name if the file name begins with a "." and has no other ".";
||| - Otherwise, the portion of the file name before the last ".".
export
fileStem : String -> Maybe String
fileStem path = pure $ fst $ splitFileName !(fileName path)

||| Extracts the extension of the file name in the path.
|||
||| The extension is:
|||
||| - Nothing, if there is no file name;
||| - Nothing, if there is no embedded ".";
||| - Nothing, if the file name begins with a "." and has no other ".";
||| - Otherwise, the portion of the file name after the last ".".
export
extension : String -> Maybe String
extension path = fileName path >>=
  filter (/= "") . Just . snd . splitFileName

||| Extracts the list of extensions of the file name in the path.
||| The returned value is:
|||
||| - Nothing, if there is no file name;
||| - Just [], if there is no embedded ".";
||| - Just [], if the filename begins with a "." and has no other ".";
||| - Just es, the portions between the "."s (excluding a potential leading one).
export
extensions : String -> Maybe (List String)
extensions path = snd . splitExtensions <$> fileName path

||| Updates the file name in the path.
|||
||| If there is no file name, it appends the name to the path;
||| otherwise, it appends the name to the parent of the path.
export
setFileName : (name : String) -> String -> String
setFileName name path = show $ setFileName' name (parse path)

||| Appends a extension to the path.
|||
||| If there is no file name, the path will not change;
||| if the path has no extension, the extension will be appended;
||| if the given extension is empty, the extension of the path will be dropped;
||| otherwise, the extension will be replaced.
|||
||| ```idris example
||| "/tmp/Foo" <.> "idr" == "/tmp/Foo.idr"
||| ```
export
(<.>) : String -> (extension : String) -> String
(<.>) path ext =
  let
    path' = parse path
    ext = pack $ dropWhile (\char => char == '.' || isSpace char) (unpack ext)
    ext = if ext == "" then "" else "." ++ ext
  in
    case fileName' path' of
      Just name =>
        let (stem, _) = splitFileName name in
          show $ setFileName' (stem ++ ext) path'
      Nothing => path

||| Appends a extension to the path, replacing multiple extensions.
|||
||| If there is no file name, the path will not change;
||| if the path has no extension, the extension will be appended;
||| if the given extension is empty, all of the extensions of the path will be dropped;
||| otherwise, the extensions will be replaced.
|||
||| ```idris example
||| "/tmp/Foo.lidr.md" <.> "idr" == "/tmp/Foo.idr"
||| ```
export
(<..>) : String -> (extension : String) -> String
(<..>) path ext =
  let
    path' = parse path
    ext = pack $ dropWhile (\char => char == '.' || isSpace char) (unpack ext)
    ext = if ext == "" then "" else "." ++ ext
  in
    case fileName' path' of
      Just name =>
        let (stem, _) = splitExtensions name in
          show $ setFileName' (stem ++ ext) path'
      Nothing => path


||| Drops the extension of the path.
export
dropExtension : String -> String
dropExtension path = path <.> ""

||| Drops all of the extensions of a path.
||| ```idris example
||| "/tmp/Foo.lidr.md" == "/tmp/Foo"
export
dropExtensions : String -> String
dropExtensions path = path <..> ""
