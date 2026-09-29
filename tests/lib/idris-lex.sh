# Idris source, lexed well enough for the source rules the spec tests
# check.

# idris_lex MODE FILE: an Idris source file, lexed well enough to tell code
# from comments, strings and characters. MODE `code` prints each line of
# code, numbered as `<n>:<text>`, with comments removed (`--` to the end of
# the line, `|||` documentation, nested `{- -}` blocks), every string
# literal replaced by "" and every character literal by 'c'. MODE `strings`
# prints each string literal as `<n>:<contents>`, escapes as written.
idris_lex() {
  awk -v mode="$1" '
    BEGIN { depth = 0 }
    {
      line = $0; out = ""; n = length(line); i = 1
      while (i <= n) {
        c = substr(line, i, 1); two = substr(line, i, 2)
        if (depth > 0) {
          if (two == "{-") { depth++; i += 2; continue }
          if (two == "-}") { depth--; i += 2; continue }
          i++; continue
        }
        if (two == "{-") { depth = 1; i += 2; continue }
        if (two == "--" && (i == 1 || substr(line, i - 1, 1) !~ /[!#$%&*+.\/<=>?@\\^|~:-]/) &&
            substr(line, i + 2, 1) !~ /[!#$%&*+.\/<=>?@\\^|~:]/) break
        if (substr(line, i, 3) == "|||") break
        if (c == "\"") {
          s = ""; i++
          while (i <= n) {
            d = substr(line, i, 1)
            if (d == "\\") { s = s substr(line, i, 2); i += 2; continue }
            if (d == "\"") { i++; break }
            s = s d; i++
          }
          if (mode == "strings") print NR ":" s
          out = out "\"\""
          continue
        }
        if (c == "'"'"'" && (i == 1 || substr(line, i - 1, 1) !~ /[A-Za-z0-9_]/)) {
          j = i + 1
          if (substr(line, j, 1) == "\\") { j++; while (j <= n && substr(line, j, 1) != "'"'"'") j++ }
          else j++
          if (substr(line, j, 1) == "'"'"'") { out = out "'"'"'c'"'"'"; i = j + 1; continue }
        }
        out = out c; i++
      }
      if (mode == "code" && out ~ /[^ \t]/) print NR ":" out
    }' "$2"
}
