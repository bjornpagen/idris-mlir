// A shared read-mostly map, as bench/gate/lowered/shmap.mlir (docs/plan.md
// 4.4, experiment 3): one goroutine builds a persistent red-black tree of n
// keys (Perceus's rbtree), then one goroutine per CPU looks up q
// pseudo-random keys in its own version of it, inserting a negative key of
// its own every thousandth step. Nodes are immutable: an insert copies its
// path, and the garbage collector reclaims what dies.
package main

import (
	"bufio"
	"fmt"
	"os"
	"runtime"
	"sync"
)

const (
	red   = 0
	black = 1
)

type Node struct {
	l, r  *Node
	key   int64
	color int8
	val   bool
}

func mk(c int8, l *Node, k int64, v bool, r *Node) *Node {
	return &Node{l: l, r: r, key: k, color: c, val: v}
}

func isRed(t *Node) bool { return t != nil && t.color == red }

func balanceLeft(l *Node, k int64, v bool, r *Node) *Node {
	if l == nil {
		return nil
	}
	if isRed(l.l) {
		ll := l.l
		return mk(red, mk(black, ll.l, ll.key, ll.val, ll.r), l.key, l.val, mk(black, l.r, k, v, r))
	}
	if isRed(l.r) {
		lr := l.r
		return mk(red, mk(black, l.l, l.key, l.val, lr.l), lr.key, lr.val, mk(black, lr.r, k, v, r))
	}
	return mk(black, mk(red, l.l, l.key, l.val, l.r), k, v, r)
}

func balanceRight(l *Node, k int64, v bool, r *Node) *Node {
	if r == nil {
		return nil
	}
	if isRed(r.l) {
		rl := r.l
		return mk(red, mk(black, l, k, v, rl.l), rl.key, rl.val, mk(black, rl.r, r.key, r.val, r.r))
	}
	if isRed(r.r) {
		rr := r.r
		return mk(red, mk(black, l, k, v, r.l), r.key, r.val, mk(black, rr.l, rr.key, rr.val, rr.r))
	}
	return mk(black, l, k, v, mk(red, r.l, r.key, r.val, r.r))
}

func ins(t *Node, k int64, v bool) *Node {
	if t == nil {
		return mk(red, nil, k, v, nil)
	}
	if t.color == red {
		if k < t.key {
			return mk(red, ins(t.l, k, v), t.key, t.val, t.r)
		}
		if k > t.key {
			return mk(red, t.l, t.key, t.val, ins(t.r, k, v))
		}
		return mk(red, t.l, k, v, t.r)
	}
	if k < t.key {
		if isRed(t.l) {
			return balanceLeft(ins(t.l, k, v), t.key, t.val, t.r)
		}
		return mk(black, ins(t.l, k, v), t.key, t.val, t.r)
	}
	if k > t.key {
		if isRed(t.r) {
			return balanceRight(t.l, t.key, t.val, ins(t.r, k, v))
		}
		return mk(black, t.l, t.key, t.val, ins(t.r, k, v))
	}
	return mk(black, t.l, k, v, t.r)
}

func insert(t *Node, k int64, v bool) *Node {
	t = ins(t, k, v)
	return mk(black, t.l, t.key, t.val, t.r)
}

// lookup t k: 0 when k is absent, else 1 + its value.
func lookup(t *Node, k int64) int {
	for t != nil {
		if k < t.key {
			t = t.l
		} else if k > t.key {
			t = t.r
		} else if t.val {
			return 2
		} else {
			return 1
		}
	}
	return 0
}

func work(local *Node, n, q, core int64) int64 {
	x := uint64(88172645463325252) + uint64(core)*0x9E3779B97F4A7C15
	var hits int64
	for j := int64(0); j < q; j++ {
		x ^= x << 13
		x ^= x >> 7
		x ^= x << 17
		if j%1000 == 999 {
			local = insert(local, -(core*q+j)-1, true)
		} else if lookup(local, int64(x%uint64(2*n))) == 2 {
			hits++
		}
	}
	return hits
}

func main() {
	var n, q int64
	in := bufio.NewReader(os.Stdin)
	fmt.Fscan(in, &n, &q)
	var t *Node
	for i := n; i > 0; i-- {
		t = insert(t, i-1, (i-1)%10 == 0)
	}
	cores := runtime.NumCPU()
	results := make([]int64, cores)
	var wg sync.WaitGroup
	for c := 0; c < cores; c++ {
		wg.Add(1)
		go func(c int) {
			defer wg.Done()
			results[c] = work(t, n, q, int64(c))
		}(c)
	}
	wg.Wait()
	var total int64
	for _, h := range results {
		total += h
	}
	fmt.Println(total)
}
