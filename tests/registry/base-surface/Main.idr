module Main

-- A program that loads the modules of base's surface, so that each of
-- their registry entries is validated when it compiles: the files, the
-- directories, the process and its environment, the clocks, errno, the
-- pointers, the references and state threads, and the modules ruled out by
-- name (signals, threads). None of them is reached, so nothing is refused.

import Prelude
import Control.Monad.ST
import Data.IORef
import System
import System.Clock
import System.Concurrency
import System.Directory
import System.Errno
import System.FFI
import System.File
import System.Signal

main : IO ()
main = putStrLn "hello"
