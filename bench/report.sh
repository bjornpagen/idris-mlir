#!/bin/sh
# Turns a run record of bench/run.sh into its results: RUN/results.md (the
# tables) and three charts, RUN/times.svg, RUN/vs-c.svg and RUN/vs-chez.svg.
# Everything shown is computed here from the record's samples, so the
# record is the one copy of what was measured; the table bench/run.sh
# prints is this script's too.
#
#     bench/report.sh RUN [PREVIOUS]
#
# A record is a directory holding
#   about        what it ran on: the header bench/run.sh prints;
#   samples.tsv  one line per timed run: benchmark, input, compiler,
#                wall-clock nanoseconds;
#   compile.tsv  one line per benchmark: this compiler's compile time in
#                nanoseconds.
# With PREVIOUS, another record, results.md also compares the two runs.
# They compare by each benchmark's time against its own run's C, never by
# seconds: the C column of one machine has moved by 2x between runs.
#
# POSIX sh and awk only: the charts are written as SVG text, so the report
# needs nothing the benchmarks do not.

set -eu

die() {
  echo "$*" >&2
  exit 1
}

[ $# -ge 1 ] && [ $# -le 2 ] || die "usage: bench/report.sh RUN [PREVIOUS]"
run=$1
previous=${2-}
for record in "$run" ${previous:+"$previous"}; do
  [ -f "$record/samples.tsv" ] && [ -f "$record/about" ] ||
    die "$record: not a run record (about and samples.tsv)"
done

labels='this compiler|Idris Chez|MLton|clang -O2|Koka|Lean 4'

# best RECORD: one line per benchmark, in the record's order: benchmark,
# input, then the best time of each compiler in $labels in seconds (empty
# when it did not run), tab-separated.
best() {
  awk -F'\t' -v labels="$labels" '
    BEGIN { n = split(labels, label, "|") }
    {
      if (!($1 in seen)) { seen[$1] = 1; order[++rows] = $1; input[$1] = $2 }
      key = $1 SUBSEP $3
      if (!(key in min) || $4 + 0 < min[key]) min[key] = $4 + 0
    }
    END {
      for (r = 1; r <= rows; r++) {
        line = order[r] "\t" input[order[r]]
        for (i = 1; i <= n; i++) {
          key = order[r] SUBSEP label[i]
          line = line "\t" ((key in min) ? sprintf("%.6f", min[key] / 1e9) : "")
        }
        print line
      }
    }' "$1/samples.tsv"
}

runs=$(awk -F'\t' '{ count[$1 SUBSEP $3]++ } END { for (k in count) if (count[k] > n) n = count[k]; print n + 0 }' "$run/samples.tsv")
best "$run" > "$run/best.tsv"

{
  cat "$run/about"
  echo
  echo "Best of $runs runs, wall-clock seconds. Outputs agree."
  echo
  echo "| benchmark | input | this compiler | Idris Chez | MLton | clang -O2 | Koka | Lean 4 | clang / this |"
  echo "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"
  awk -F'\t' '
    function cell(t) { return t == "" ? "n/a" : sprintf("%.3f", t) }
    {
      ratio = ($6 != "" && $3 != "" && $3 > 0) ? sprintf("%.2fx", $6 / $3) : "n/a"
      printf "| %s | %s | %s | %s | %s | %s | %s | %s | %s |\n", $1, $2, cell($3), cell($4), cell($5), cell($6), cell($7), cell($8), ratio
    }' "$run/best.tsv"
  if [ -s "$run/compile.tsv" ]; then
    echo
    echo "Compile time of this compiler, wall-clock seconds, once: idris-mlir, idris-mlir-cc and the link."
    echo
    echo "| benchmark | compile |"
    echo "| --- | ---: |"
    awk -F'\t' '{ printf "| %s | %.3f |\n", $1, $2 / 1e9 }' "$run/compile.tsv"
  fi
  if [ -n "$previous" ]; then
    best "$previous" > "$run/previous.tsv"
    echo
    echo "Against the previous record ($(head -n 1 "$previous/about" | sed 's/^Measured/measured/; s/\.$//')): clang's time"
    echo "over this compiler's in each run, and how it moved."
    echo
    echo "| benchmark | before | now | change |"
    echo "| --- | ---: | ---: | ---: |"
    awk -F'\t' '
      NR == FNR { if ($3 != "" && $6 != "" && $3 > 0) before[$1] = $6 / $3; next }
      {
        if ($3 == "" || $6 == "" || $3 <= 0) next
        now = $6 / $3
        if ($1 in before)
          printf "| %s | %.2fx | %.2fx | %+.0f%% |\n", $1, before[$1], now, (now / before[$1] - 1) * 100
        else
          printf "| %s | n/a | %.2fx | new |\n", $1, now
      }' "$run/previous.tsv" "$run/best.tsv"
    rm -f "$run/previous.tsv"
  fi
} > "$run/results.md"

# chart MODE: an SVG on stdout from best.tsv. MODE times draws every
# compiler's best time per benchmark on a log axis of seconds; vs-c and
# vs-chez draw the other compiler's time over this compiler's, sorted, on
# a log axis around 1x, where a bar to the right means this compiler is
# faster.
chart() {
  awk -F'\t' -v mode="$1" -v labels="$labels" -v title="$2" '
    function log10(x) { return log(x) / log(10) }
    function floor_(x) { return x == int(x) ? x : (x < 0 ? int(x) - 1 : int(x)) }
    function ceil_(x) { return x == int(x) ? x : (x < 0 ? int(x) : int(x) + 1) }
    function esc(s) { gsub(/&/, "\\&amp;", s); gsub(/</, "\\&lt;", s); gsub(/>/, "\\&gt;", s); return s }
    function text(x, y, s, anchor, size, fill, weight) {
      printf "<text x=\"%.1f\" y=\"%.1f\" text-anchor=\"%s\" font-size=\"%d\" fill=\"%s\"%s>%s</text>\n", x, y, anchor, size, fill, weight == "" ? "" : " font-weight=\"" weight "\"", esc(s)
    }
    function seconds(t) {
      if (t >= 1) return sprintf("%g s", t)
      if (t >= 0.001) return sprintf("%g ms", t * 1000)
      return sprintf("%g µs", t * 1e6)
    }
    BEGIN {
      n = split(labels, label, "|")
      split("#58a6ff|#d29922|#a371f7|#8b949e|#f778ba|#3fb950", colour, "|")
      bg = "#0d1117"; fg = "#c9d1d9"; dim = "#8b949e"; grid = "#30363d"
      good = "#3fb950"; bad = "#f85149"
    }
    {
      rows++
      name[rows] = $1
      for (i = 1; i <= n; i++) t[rows, i] = $(i + 2)
    }
    END {
      left = 190; width = 560; right = 90; top = 70
      if (mode == "times") {
        lo = 1e30; hi = 0
        for (r = 1; r <= rows; r++)
          for (i = 1; i <= n; i++)
            if (t[r, i] != "" && t[r, i] > 0) {
              if (t[r, i] < lo) lo = t[r, i]
              if (t[r, i] > hi) hi = t[r, i]
            }
        a = floor_(log10(lo)); b = ceil_(log10(hi))
        bar = 4; row = n * bar + 10
        height = top + rows * row + 50
        printf "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"%d\" viewBox=\"0 0 %d %d\" font-family=\"-apple-system, Segoe UI, Helvetica, Arial, sans-serif\">\n", left + width + right, height, left + width + right, height
        printf "<rect width=\"100%%\" height=\"100%%\" fill=\"%s\"/>\n", bg
        text(left, 24, title, "start", 16, fg, "600")
        x = left
        for (i = 1; i <= n; i++) {
          printf "<rect x=\"%.1f\" y=\"36\" width=\"10\" height=\"10\" fill=\"%s\"/>\n", x, colour[i]
          text(x + 14, 45, label[i], "start", 12, fg, "")
          x += 14 + length(label[i]) * 7 + 18
        }
        for (d = a; d <= b; d++) {
          gx = left + (d - a) / (b - a) * width
          printf "<line x1=\"%.1f\" y1=\"%d\" x2=\"%.1f\" y2=\"%d\" stroke=\"%s\"/>\n", gx, top - 6, gx, top + rows * row, grid
          text(gx, top + rows * row + 18, seconds(10 ^ d), "middle", 11, dim, "")
        }
        for (r = 1; r <= rows; r++) {
          y = top + (r - 1) * row
          text(left - 10, y + row / 2 + 3, name[r], "end", 12, fg, "")
          for (i = 1; i <= n; i++) {
            if (t[r, i] == "" || t[r, i] <= 0) continue
            w = (log10(t[r, i]) - a) / (b - a) * width
            printf "<rect x=\"%d\" y=\"%.1f\" width=\"%.1f\" height=\"%d\" fill=\"%s\"><title>%s, %s: %.3f s</title></rect>\n", left, y + 5 + (i - 1) * bar, w, bar - 1, colour[i], esc(name[r]), esc(label[i]), t[r, i]
          }
        }
        text(left + width / 2, height - 12, "best wall-clock time, log scale; a missing bar: that compiler has no version of the program", "middle", 11, dim, "")
        print "</svg>"
        exit
      }
      other = mode == "vs-c" ? 4 : 2
      m = 0; missing = ""
      for (r = 1; r <= rows; r++) {
        if (t[r, 1] == "" || t[r, other] == "" || t[r, 1] <= 0) {
          missing = missing (missing == "" ? "" : ", ") name[r]
          continue
        }
        m++; key[m] = name[r]; ratio[m] = t[r, other] / t[r, 1]
      }
      for (i = 2; i <= m; i++)
        for (j = i; j > 1 && ratio[j] > ratio[j - 1]; j--) {
          s = ratio[j]; ratio[j] = ratio[j - 1]; ratio[j - 1] = s
          s = key[j]; key[j] = key[j - 1]; key[j - 1] = s
        }
      lo = 1; hi = 1
      for (i = 1; i <= m; i++) {
        if (ratio[i] < lo) lo = ratio[i]
        if (ratio[i] > hi) hi = ratio[i]
      }
      a = floor_(log10(lo)); b = ceil_(log10(hi))
      if (a == b) b = a + 1
      row = 22
      height = top + m * row + (missing == "" ? 50 : 70)
      printf "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"%d\" viewBox=\"0 0 %d %d\" font-family=\"-apple-system, Segoe UI, Helvetica, Arial, sans-serif\">\n", left + width + right, height, left + width + right, height
      printf "<rect width=\"100%%\" height=\"100%%\" fill=\"%s\"/>\n", bg
      text(left, 24, title, "start", 16, fg, "600")
      text(left, 46, "right of 1x: this compiler is faster; log scale", "start", 12, dim, "")
      one = left + (0 - a) / (b - a) * width
      for (d = a; d <= b; d++) {
        gx = left + (d - a) / (b - a) * width
        printf "<line x1=\"%.1f\" y1=\"%d\" x2=\"%.1f\" y2=\"%d\" stroke=\"%s\"/>\n", gx, top - 6, gx, top + m * row, d == 0 ? dim : grid
        text(gx, top + m * row + 18, sprintf("%gx", 10 ^ d), "middle", 11, dim, "")
      }
      for (i = 1; i <= m; i++) {
        y = top + (i - 1) * row
        x = left + (log10(ratio[i]) - a) / (b - a) * width
        text(left - 10, y + 15, key[i], "end", 12, fg, "")
        if (x >= one) printf "<rect x=\"%.1f\" y=\"%d\" width=\"%.1f\" height=\"14\" fill=\"%s\"/>\n", one, y + 4, x - one, good
        else printf "<rect x=\"%.1f\" y=\"%d\" width=\"%.1f\" height=\"14\" fill=\"%s\"/>\n", x, y + 4, one - x, bad
        text(x >= one ? x + 6 : one + 6, y + 15, ratio[i] >= 10 ? sprintf("%.0fx", ratio[i]) : sprintf("%.2fx", ratio[i]), "start", 12, fg, "")
      }
      if (missing != "")
        text(left, top + m * row + 44, "not shown, no version to compare with: " missing, "start", 11, dim, "")
      print "</svg>"
    }' "$run/best.tsv"
}

chart times "Best time of each compiler, per benchmark" > "$run/times.svg"
chart vs-c "clang -O2's time over this compiler's" > "$run/vs-c.svg"
chart vs-chez "Idris on Chez Scheme's time over this compiler's" > "$run/vs-chez.svg"
rm -f "$run/best.tsv"

cat "$run/results.md"
