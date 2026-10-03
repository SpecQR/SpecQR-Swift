func withinLimit(_ dimension: Int32) -> Bool {
   Int64(dimension) <= 9_007_199_254_740_991
}
assert(withinLimit(Int32.max))
