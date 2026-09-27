// A pipeline passing trees between cores, as bench/gate/lowered/pipe.mlir
// (docs/plan.md 4.4, experiment 3): goroutines pair up; the first of a pair
// builds count trees make_ i depth and sends them on a channel of 64
// entries, the second checks them. The garbage collector reclaims the
// trees.
package main

import (
	"bufio"
	"fmt"
	"os"
	"runtime"
	"sync"
)

type Node struct{ l, r *Node }

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

func main() {
	var count, depth int64
	fmt.Fscan(bufio.NewReader(os.Stdin), &count, &depth)
	pairs := runtime.NumCPU() / 2
	if pairs < 1 {
		pairs = 1
	}
	results := make([]int64, pairs)
	var wg sync.WaitGroup
	for p := 0; p < pairs; p++ {
		ch := make(chan *Node, 64)
		wg.Add(2)
		go func() {
			defer wg.Done()
			for i := int64(1); i <= count; i++ {
				ch <- make_(i, depth)
			}
			close(ch)
		}()
		go func(p int) {
			defer wg.Done()
			var s int64
			for t := range ch {
				s += check(t)
			}
			results[p] = s
		}(p)
	}
	wg.Wait()
	var total int64
	for _, s := range results {
		total += s
	}
	fmt.Println(total)
}
