||| TC-PIN-1, TC-DEV-2: toolchain.lock.json pins every tool the build uses,
||| by revision, repository, tag and version, and the configure gate's
||| accepted series matches the pinned version.
|||
|||     runtests --lock
|||
||| rule: TC-PIN-1, TC-DEV-2
module Lock

import Data.List
import Data.Maybe
import Data.String
import Language.JSON
import System
import System.File

%default covering

field : String -> JSON -> Maybe JSON
field key (JObject fields) = lookup key fields
field _ _ = Nothing

text : String -> JSON -> Maybe String
text key json = case field key json of
  Just (JString s) => Just s
  _ => Nothing

hexRevision : String -> Bool
hexRevision s = length s == 40 && all (\c => isDigit c || (c >= 'a' && c <= 'f')) (unpack s)

||| What is wrong with one tool's entry, or Nothing.
pinned : JSON -> String -> List String
pinned lock tool = case field tool lock of
  Nothing => ["no entry"]
  Just entry =>
    (if maybe False hexRevision (text "revision" entry) then [] else ["revision is not 40 hex digits"])
      ++ [ key ++ " is missing" | key <- ["repository", "tag", "version"]
         , maybe True (== "") (text key entry) ]

accepted : JSON -> String -> Bool
accepted lock tool = fromMaybe False $ do
  entry <- field tool lock
  version <- text "version" entry
  series <- text "accept" entry
  pure (series `isPrefixOf` version)

export
check : (root : String) -> IO ()
check root = do
  let path = root ++ "/toolchain.lock.json"
  Right contents <- readFile path
    | Left err => die "\{path}: \{show err}"
  let Just lock = parse contents
    | Nothing => putStrLn "toolchain.lock.json: not JSON"
  putStrLn $ case field "schema_version" lock of
    Just (JNumber 3) => "schema_version: 3"
    other => "schema_version: \{maybe "missing" show other}, not 3"
  for_ ["gcc", "cmake", "ninja", "llvm"] $ \tool =>
    putStrLn $ case pinned lock tool of
      [] => tool ++ ": pinned by revision, repository, tag and version"
      problems => tool ++ ": " ++ joinBy "; " problems
  for_ ["gcc", "cmake", "ninja"] $ \tool =>
    putStrLn $ tool ++ (if accepted lock tool then ": version in the accepted series"
                                              else ": version outside the accepted series")
