# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# C++ source, lexed well enough for the source rules the spec tests check.

# cpp_lex FILE...: C and C++ sources, lexed well enough to tell code from
# comments and literals. Each line of each file is printed, numbered as
# `<file>:<n>:<text>`, with comments removed (`//` to the end of the line,
# `/* */` across lines), every string literal replaced by "" (a raw string
# across lines included) and every character literal by ''. A quote after a
# letter or a digit is a digit separator, not a character.
cpp_lex() {
  awk '
    FNR == 1 { block = 0; raw = "" }
    {
      line = $0; out = ""; n = length(line); i = 1
      while (i <= n) {
        if (block) {
          k = index(substr(line, i), "*/")
          if (k == 0) { i = n + 1; continue }
          i += k + 1; block = 0; out = out " "; continue
        }
        if (raw != "") {
          k = index(substr(line, i), raw)
          if (k == 0) { i = n + 1; continue }
          i += k - 1 + length(raw); raw = ""; out = out "\"\""; continue
        }
        c = substr(line, i, 1); two = substr(line, i, 2)
        if (two == "//") break
        if (two == "/*") { block = 1; i += 2; continue }
        if (c == "\"" && substr(line, 1, i - 1) ~ /(^|[^A-Za-z0-9_])(u8|u|U|L)?R$/) {
          k = index(substr(line, i + 1), "(")
          raw = ")" substr(line, i + 1, k - 1) "\""
          i += k + 1; continue
        }
        if (c == "\"") {
          i++
          while (i <= n) {
            d = substr(line, i, 1)
            if (d == "\\") { i += 2; continue }
            i++
            if (d == "\"") break
          }
          out = out "\"\""
          continue
        }
        if (c == "'"'"'" && (i == 1 || substr(line, i - 1, 1) !~ /[A-Za-z0-9_]/)) {
          i++
          while (i <= n) {
            d = substr(line, i, 1)
            if (d == "\\") { i += 2; continue }
            i++
            if (d == "'"'"'") break
          }
          out = out "'"'"''"'"'"
          continue
        }
        out = out c; i++
      }
      print FILENAME ":" FNR ":" out
    }' "$@"
}
