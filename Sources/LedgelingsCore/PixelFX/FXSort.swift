// JavaScript's `Array.prototype.sort` as V8 runs it, for the few effects that sort with a random
// comparator (`sort(() => R.next() - 0.5)`): which items come first then depends on the order the
// comparator is asked in, so to pick the same spots as pixelfx we ask it in the same order. Under 64
// items V8's TimSort is one run made by binary insertion, reproduced here exactly; longer lists are sorted
// stably, which gives the same result for any consistent comparator.

import Foundation

extension FX {
    /// Sorted the V8 way; `order(a, b) < 0` puts a first.
    public static func jsSort<T>(_ items: [T], _ order: (T, T) -> Double) -> [T] {
        var work = items
        let n = work.count
        if n < 2 { return work }
        if n >= 64 {
            return work.enumerated().sorted { l, r in
                let o = order(l.element, r.element)
                return o < 0 || (o == 0 && l.offset < r.offset)
            }.map(\.element)
        }
        // CountAndMakeRun from 0
        var runLength = 2
        let descending = order(work[1], work[0]) < 0
        var previous = work[1]
        var idx = 2
        while idx < n {
            let current = work[idx]
            let o = order(current, previous)
            if descending ? o >= 0 : o < 0 { break }
            previous = current
            runLength += 1
            idx += 1
        }
        if descending { work[0..<runLength].reverse() }
        // BinaryInsertionSort(0, runLength, n)
        var start = runLength
        while start < n {
            let pivot = work[start]
            var left = 0, right = start
            while left < right {
                let mid = left + ((right - left) >> 1)
                if order(pivot, work[mid]) < 0 { right = mid } else { left = mid + 1 }
            }
            var p = start
            while p > left { work[p] = work[p - 1]; p -= 1 }
            work[left] = pivot
            start += 1
        }
        return work
    }
}
