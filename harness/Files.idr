-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Reading the files a test holds and a run left, for the runner's
||| commands: text, or bytes where a program's output may hold NUL.
module Files

import System
import System.File

%default covering

||| A file's text, or the runner's death naming it.
export
readOrDie : String -> IO String
readOrDie path = do
  Right text <- readFile path
    | Left err => die (path ++ ": " ++ show err)
  pure text

||| A file's text, or nothing when it does not exist.
export
readIfThere : String -> IO (Maybe String)
readIfThere path = do
  Right text <- readFile path
    | Left _ => pure Nothing
  pure (Just text)

||| A file's bytes, each the Char of its value: a program's output, which
||| may hold NUL, where a read of the file's text (readFile, through C's
||| lines) loses the rest of its line; or the runner's death naming it.
export
bytesOrDie : String -> IO String
bytesOrDie path = do
  Right h <- openFile path Read
    | Left err => die (path ++ ": " ++ show err)
  bytes <- go h [<]
  closeFile h
  pure (pack bytes)
  where
    go : File -> SnocList Char -> IO (List Char)
    go h acc = do
      Right c <- fGetChar h
        | Left err => die (path ++ ": " ++ show err)
      True <- fEOF h
        | False => go h (acc :< c)
      pure (acc <>> [])

||| A file's bytes, or none when it does not exist.
export
bytesIfThere : String -> IO String
bytesIfThere path = do
  True <- exists path
    | False => pure ""
  bytesOrDie path
