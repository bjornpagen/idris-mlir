-- stdout: hello from Greet\n
module Main

import IdrisMLIR.IO
import Greet

main : IO ()
main = greet "Greet"
