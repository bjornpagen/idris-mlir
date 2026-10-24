-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| toolchain.lock.json pins every tool the build uses:
||| each entry records the exact version, the source repository, the commit,
||| and a tag or a `git describe`.
|||
|||     runtests --lock
module Lock

import Data.List
import Data.SortedMap
import Data.String
import Json
import System
import System.File

%default covering

||| How a tool's pinned commit is named: by its release tag, or by
||| `git describe`.
data PinRef = Tag String | Describe String

||| One tool's entry, read.
record Pin where
  constructor MkPin
  revision, repository, version : String
  ref : PinRef

hexRevision : String -> Bool
hexRevision s = length s == 40 && all (\c => isDigit c || (c >= 'a' && c <= 'f')) (unpack s)

||| Two readings side by side: both values, or the problems of each.
both : Either (List String) (a -> b) -> Either (List String) a -> Either (List String) b
both (Right f) (Right x) = Right (f x)
both (Left p) (Left q) = Left (p ++ q)
both (Left p) (Right _) = Left p
both (Right _) (Left q) = Left q

||| One tool's entry: its pin, or the line that says what is wrong with it.
pin : (String, JSON) -> Either (List String) Pin
pin (name, JObject fields) =
  either (\problems => Left [name ++ ": " ++ joinBy "; " problems]) Right $
    both (both (both (MkPin <$> revision) (given "repository")) (given "version")) ref
  where
    byKey : SortedMap String JSON
    byKey = fromList fields
    textAt : String -> Maybe String
    textAt key = case lookup key byKey of
      Just (JString s) => Just s
      _ => Nothing
    revision : Either (List String) String
    revision = case textAt "revision" of
      Just r => if hexRevision r then Right r else Left ["revision is not 40 hex digits"]
      Nothing => Left ["revision is not 40 hex digits"]
    given : String -> Either (List String) String
    given key = case textAt key of
      Just v => if v == "" then Left [key ++ " is missing"] else Right v
      Nothing => Left [key ++ " is missing"]
    ref : Either (List String) PinRef
    ref = case (textAt "tag", textAt "describe") of
      (Just t, Nothing) => Right (Tag t)
      (Nothing, Just d) => Right (Describe d)
      (Nothing, Nothing) => Left ["neither tag nor describe"]
      (Just _, Just _) => Left ["both tag and describe"]
pin (name, _) = Left [name ++ ": not an object"]

report : String -> List String -> IO ()
report verdict [] = putStrLn verdict
report _ bad = traverse_ putStrLn bad

export
check : (root : String) -> IO ()
check root = do
  let path = root ++ "/toolchain.lock.json"
  Right contents <- readFile path
    | Left err => die "\{path}: \{show err}"
  let Right (JObject fields) = parse contents
    | _ => putStrLn "toolchain.lock.json: not a JSON object"
  putStrLn $ case lookup "schema_version" fields >>= integer of
    Just n => "schema_version: " ++ show n
    Nothing => "schema_version: missing"
  -- Every entry but the schema's is a tool's.
  let tools = map (\entry => (fst entry, pin entry)) (filter ((/= "schema_version") . fst) fields)
  report "every tool is pinned by revision, repository, version, and tag or describe"
    (tools >>= \(_, read) => either id (const []) read)
