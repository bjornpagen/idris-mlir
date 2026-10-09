module Main

-- A directory made, three directories made in it, and it listed with
-- openDir and nextDirEntry until Nothing, then closed and everything
-- removed. The names are sorted before they are printed, since the order
-- of a directory's entries is the file system's. Each name is a string the
-- runtime keeps until the next entry or the close, so the program ends
-- with no live cell. Once removed, the directory does not open.

import Prelude
import Data.List
import System.Directory

entries : Directory -> List String -> IO (Either FileError (List String))
entries d acc = do
  Right (Just name) <- nextDirEntry d
    | Right Nothing => pure (Right acc)
    | Left err => pure (Left err)
  entries d (name :: acc)

main : IO ()
main = do
  Right () <- createDir "listing"
    | Left _ => putStrLn "createDir failed"
  for_ ["listing/gamma", "listing/alpha", "listing/beta"] $ \sub => do
    Right () <- createDir sub
      | Left _ => putStrLn ("createDir failed: " ++ sub)
    pure ()
  Right dir <- openDir "listing"
    | Left _ => putStrLn "openDir failed"
  Right names <- entries dir []
    | Left _ => putStrLn "nextDirEntry failed"
  closeDir dir
  traverse_ putStrLn (sort names)
  printLn (length names)
  removeDir "listing/alpha"
  removeDir "listing/beta"
  removeDir "listing/gamma"
  removeDir "listing"
  Left _ <- openDir "listing"
    | Right again => closeDir again >> putStrLn "still there"
  putStrLn "removed"
