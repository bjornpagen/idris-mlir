||| toolchain.lock.json pins every tool the build uses:
||| each entry records the exact version, the source repository, the commit,
||| and a tag or a `git describe`; where the configure gate accepts a release
||| series (`accept`), the pinned version is in it.
|||
|||     runtests --lock
module Lock

import Data.List
import Data.Maybe
import Data.String
import Language.JSON
import System
import System.File

%default covering

text : String -> JSON -> Maybe String
text key (JObject fields) = case lookup key fields of
  Just (JString s) => Just s
  _ => Nothing
text _ _ = Nothing

hexRevision : String -> Bool
hexRevision s = length s == 40 && all (\c => isDigit c || (c >= 'a' && c <= 'f')) (unpack s)

||| What is wrong with one tool's entry.
problems : JSON -> List String
problems entry =
  (if maybe False hexRevision (text "revision" entry) then [] else ["revision is not 40 hex digits"])
    ++ [ key ++ " is missing" | key <- ["repository", "version"], maybe True (== "") (text key entry) ]
    ++ (if isJust (text "tag" entry) || isJust (text "describe" entry)
           then [] else ["neither tag nor describe"])

||| Whether the accepted series, if any, holds the version.
accepted : JSON -> Bool
accepted entry = fromMaybe True $ do
  series <- text "accept" entry
  version <- text "version" entry
  pure (series `isPrefixOf` version)

||| The tools: the entries that are objects.
objects : List (String, JSON) -> List (String, JSON)
objects [] = []
objects ((name, entry@(JObject _)) :: rest) = (name, entry) :: objects rest
objects (_ :: rest) = objects rest

report : String -> List String -> IO ()
report verdict [] = putStrLn verdict
report _ bad = traverse_ putStrLn bad

export
check : (root : String) -> IO ()
check root = do
  let path = root ++ "/toolchain.lock.json"
  Right contents <- readFile path
    | Left err => die "\{path}: \{show err}"
  let Just (JObject fields) = parse contents
    | _ => putStrLn "toolchain.lock.json: not a JSON object"
  putStrLn $ case lookup "schema_version" fields of
    Just (JNumber n) => "schema_version: " ++ show (the Integer (cast n))
    _ => "schema_version: missing"
  let tools = objects fields
  report "every tool is pinned by revision, repository, version, and tag or describe"
    [ name ++ ": " ++ joinBy "; " bad | (name, entry) <- tools, let bad = problems entry, not (null bad) ]
  report "every accepted release series holds its tool's pinned version"
    [ name ++ ": version outside the accepted series" | (name, entry) <- tools, not (accepted entry) ]
