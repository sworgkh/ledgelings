// JavaScript's `Array.prototype.sort` as V8 runs it, for the few effects that sort with a random
// comparator (`sort(() => R.next() - 0.5)`): which items come first then depends on the order the
// comparator is asked in, so to pick the same spots as pixelfx we ask it in the same order. Under 64
// items V8's TimSort is one run made by binary insertion, reproduced here exactly; longer lists are sorted
// stably, which gives the same result for any consistent comparator.

namespace Ledgelings.Core.PixelFX;

public static partial class FX
{
    /// <summary>Sorted the V8 way; <c>order(a, b) &lt; 0</c> puts a first. Never List.Sort or LINQ's order for a JS sort.</summary>
    public static List<T> JsSort<T>(IEnumerable<T> items, Func<T, T, double> order)
    {
        var work = items.ToList();
        var n = work.Count;
        if (n < 2) return work;
        if (n >= 64)
        {
            var indexed = work.Select((e, i) => (e, i)).ToList();
            indexed.Sort((l, r) =>
            {
                if (l.i == r.i) return 0;
                var o = order(l.e, r.e);
                return o < 0 ? -1 : o > 0 ? 1 : l.i.CompareTo(r.i);
            });
            return indexed.Select(p => p.e).ToList();
        }
        // CountAndMakeRun from 0
        var runLength = 2;
        var descending = order(work[1], work[0]) < 0;
        var previous = work[1];
        for (var idx = 2; idx < n; idx++)
        {
            var current = work[idx];
            var o = order(current, previous);
            if (descending ? o >= 0 : o < 0) break;
            previous = current;
            runLength += 1;
        }
        if (descending) work.Reverse(0, runLength);
        // BinaryInsertionSort(0, runLength, n)
        for (var start = runLength; start < n; start++)
        {
            var pivot = work[start];
            int left = 0, right = start;
            while (left < right)
            {
                var mid = left + ((right - left) >> 1);
                if (order(pivot, work[mid]) < 0) right = mid; else left = mid + 1;
            }
            for (var p = start; p > left; p--) work[p] = work[p - 1];
            work[left] = pivot;
        }
        return work;
    }
}
