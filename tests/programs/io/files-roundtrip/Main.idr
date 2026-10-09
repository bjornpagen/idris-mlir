module Main

-- A file written, then read back by line and by characters, its size read
-- from an open handle, and the file removed, through base's System.File.
-- A line keeps its newline, and the last one, which has none, ends where
-- the file does; a read of characters at the end gives "". Once removed,
-- the file is not found.

import Prelude
import System.File

readLines : File -> List String -> IO (List String)
readLines f acc = do
  False <- fEOF f
    | True => pure (reverse acc)
  Right l <- fGetLine f
    | Left _ => pure (reverse ("read failed" :: acc))
  readLines f (l :: acc)

main : IO ()
main = do
  Right out <- openFile "roundtrip.txt" WriteTruncate
    | Left _ => putStrLn "open for writing failed"
  Right () <- fPutStrLn out "first line"
    | Left _ => putStrLn "write failed"
  Right () <- fPutStr out "second line\nno newline"
    | Left _ => putStrLn "write failed"
  closeFile out
  Right byLine <- openFile "roundtrip.txt" Read
    | Left _ => putStrLn "open for reading failed"
  Right size <- fileSize byLine
    | Left _ => putStrLn "fileSize failed"
  printLn size
  printLn !(readLines byLine [])
  closeFile byLine
  Right byChar <- openFile "roundtrip.txt" Read
    | Left _ => putStrLn "open for reading failed"
  Right a <- fGetChars byChar 5
    | Left _ => putStrLn "read failed"
  Right b <- fGetChars byChar 100
    | Left _ => putStrLn "read failed"
  Right c <- fGetChars byChar 4
    | Left _ => putStrLn "read failed"
  printLn a
  printLn b
  printLn c
  printLn !(fEOF byChar)
  closeFile byChar
  Right () <- removeFile "roundtrip.txt"
    | Left _ => putStrLn "removeFile failed"
  Left FileNotFound <- openFile "roundtrip.txt" Read
    | Left _ => putStrLn "open failed otherwise"
    | Right f => closeFile f >> putStrLn "still there"
  putStrLn "removed"
