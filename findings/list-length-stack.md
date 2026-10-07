# The Prelude's length keeps a frame per element

`length` on a list is not a tail call: the element stays until the rest is
counted. The program's stack is a gibibyte (the process limit when that is
larger). A list of 32724036 characters is counted; a list of 33677161
characters ends with `idris-mlir: stack exhausted`.

Reading those characters and reversing the list does not, and neither does
counting them in an `Int` accumulator. The official regex-redux input is
50833411 characters. Its matcher and its replacements finish; the crash is
the first `length`. `bench/regex-redux` counts with an accumulator so the
run can finish. The program below is the crash, on however many characters
stdin holds.

```idris
module Main

import Prelude

readAll : List Char -> IO (List Char)
readAll acc = do
  c <- getChar
  if ord c == 255 then pure (reverse acc) else readAll (c :: acc)

main : IO ()
main = do
  input <- readAll []
  printLn (length input)
```
