// Parallel binary trees, as bench/gate/lowered/ptrees.mlir (experiment
// 3): each depth's trees are split into 8 work items that
// one goroutine per CPU takes from a shared index. The output is that of
// the suite's binarytrees.
package main

import (
	"bufio"
	"fmt"
	"os"
	"runtime"
	"sync"
	"sync/atomic"
)

type Node struct{ l, r *Node }

// make_ n d: the seed n keeps the two subtrees distinct, as in the suite.
func make_(n, d int64) *Node {
	if d == 0 {
		return &Node{}
	}
	return &Node{make_(n, d-1), make_(n+1, d-1)}
}

func check(t *Node) int64 {
	if t == nil {
		return 0
	}
	return 1 + check(t.l) + check(t.r)
}

// The checks of the trees make_ j d for j in (lo, hi].
func sumRange(d, hi, lo int64) int64 {
	var t int64
	for j := hi; j > lo; j-- {
		t += check(make_(j, d))
	}
	return t
}

type item struct{ d, hi, lo int64 }

func main() {
	var n int64
	fmt.Fscan(bufio.NewReader(os.Stdin), &n)
	out := bufio.NewWriter(os.Stdout)
	defer out.Flush()
	minN := int64(4)
	maxN := n
	if maxN < minN+2 {
		maxN = minN + 2
	}
	stretch := maxN + 1
	fmt.Fprintf(out, "stretch tree of depth %d\t check: %d\n", stretch, check(make_(stretch, stretch)))
	long := make_(maxN, maxN)

	ndepths := (maxN-minN)/2 + 1
	items := make([]item, 0, ndepths*8)
	for k := int64(0); k < ndepths; k++ {
		d := minN + 2*k
		part := (int64(1) << (maxN - d + minN)) / 8
		for p := int64(0); p < 8; p++ {
			items = append(items, item{d, (p + 1) * part, p * part})
		}
	}
	results := make([]int64, len(items))
	next := int64(-1)
	var wg sync.WaitGroup
	for w := 0; w < runtime.NumCPU(); w++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for {
				i := atomic.AddInt64(&next, 1)
				if i >= int64(len(items)) {
					return
				}
				it := items[i]
				results[i] = sumRange(it.d, it.hi, it.lo)
			}
		}()
	}
	wg.Wait()
	for k := int64(0); k < ndepths; k++ {
		var s int64
		for p := int64(0); p < 8; p++ {
			s += results[8*k+p]
		}
		d := minN + 2*k
		fmt.Fprintf(out, "%d\t trees of depth %d\t check: %d\n", int64(1)<<(maxN-d+minN), d, s)
	}
	fmt.Fprintf(out, "long lived tree of depth %d\t check: %d\n", maxN, check(long))
}
