import
  ranges/ptr_arith

type
  Bytes* = seq[byte]

  BytesRange* = object
    bytes*: Bytes
    ibegin*, iend*: int

proc initBytesRange*(s: var Bytes, ibegin = 0, iend = -1): BytesRange =
  let e = if iend < 0: s.len + iend + 1
          else: iend
  assert ibegin >= 0 and e <= s.len

  shallow(s)
  result.bytes = s
  result.ibegin = ibegin
  result.iend = e

var
  zeroBytes*: Bytes = @[]
  zeroBytesRange* = initBytesRange(zeroBytes)

proc `[]`*(r: BytesRange, i: int): byte =
  r.bytes[r.ibegin + i]

proc `[]`*(r: var BytesRange, i: int): var byte =
  r.bytes[r.ibegin + i]

# XXX: change this to a template after fixing
# https://github.com/nim-lang/Nim/issues/7097
proc `[]=`*(r: var BytesRange, i: int, v: byte) =
  r.bytes[r.ibegin + i] = v

template len*(r: BytesRange): int =
  r.iend - r.ibegin

proc slice*(r: BytesRange, ibegin: int, iend = -1): BytesRange =
  result.bytes = r.bytes
  result.ibegin = r.ibegin + ibegin
  let e = if iend < 0: r.iend + iend + 1
          else: r.ibegin + iend
  assert ibegin >= 0 and e <= result.bytes.len
  result.iend = e

iterator items*(r: BytesRange): byte =
  for i in r.ibegin ..< r.iend:
    yield r.bytes[i]

proc toRange*(s: Bytes): BytesRange =
  var seqCopy = s
  return initBytesRange(seqCopy)

proc toRange*(s: var Bytes): BytesRange =
  return initBytesRange(s)

# XXX: This could be a template once the following issue is fixed:
# https://github.com/nim-lang/Nim/issues/7223
proc rangeBeginAddr*(r: BytesRange): pointer {.inline.} =
  baseAddr(r.bytes).shift(r.ibegin)

proc baseAddr*(r: BytesRange): pointer =
  baseAddr(r.bytes).shift(r.ibegin)

when false:
  import
    ptr_arith, keccak_tiny

  type
    KeccakHash* = Hash[256]

  proc toInputRange*(r: BytesRange): keccak_tiny.InputRange =
    result[0] = r.bytes.seqBaseAddr.shift(r.ibegin)
    result[1] = r.len

  proc keccak*(r: BytesRange): KeccakHash = keccak_256(r)

