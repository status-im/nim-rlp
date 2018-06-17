## This module implements RLP encoding and decoding as
## defined in Appendix B of the Ethereum Yellow Paper:
## https://ethereum.github.io/yellowpaper/paper.pdf

import
  strutils, parseutils,
  rlp/[types, writer, object_serialization],
  rlp/priv/defs

export
  types, writer, object_serialization

type
  Rlp* = object
    bytes: BytesRange
    position: int

  RlpNodeType* = enum
    rlpBlob
    rlpList

  RlpNode* = object
    case kind*: RlpNodeType
    of rlpBlob:
      bytes*: BytesRange
    of rlpList:
      elems*: seq[RlpNode]

  RlpError* = object of Exception
  MalformedRlpError* = object of RlpError
  UnsupportedRlpError* = object of RlpError
  RlpTypeMismatch* = object of RlpError

proc rlpFromBytes*(data: BytesRange): Rlp =
  result.bytes = data
  result.position = 0

const zeroBytesRlp* = Rlp()

proc rlpFromHex*(input: string): Rlp =
  doAssert input.len mod 2 == 0,
          "rlpFromHex expects a string with even number of characters (assuming two characters per byte)"

  let totalBytes = input.len div 2
  var backingStore = newSeq[byte](totalBytes)

  for i in 0 ..< totalBytes:
    var nextByte: int
    if parseHex(input, nextByte, i*2, 2) == 2:
      backingStore[i] = byte(nextByte)
    else:
      doAssert false, "rlpFromHex expects a hexademical string, but the input contains non hexademical characters"

  result.bytes = backingStore.toRange()

{.this: self.}

proc hasData*(self: Rlp): bool =
  position < bytes.len

template rawData*(self: Rlp): BytesRange =
  self.bytes

proc isBlob*(self: Rlp): bool =
  hasData() and bytes[position] < LIST_START_MARKER

proc isEmpty*(self: Rlp): bool =
  ### Contains a blob or a list of zero length
  hasData() and (bytes[position] == BLOB_START_MARKER or
                 bytes[position] == LIST_START_MARKER)

proc isList*(self: Rlp): bool =
  hasData() and bytes[position] >= LIST_START_MARKER

template eosError =
  raise newException(MalformedRlpError, "Read past the end of the RLP stream")

template requireData {.dirty.} =
  if not hasData():
    raise newException(MalformedRlpError, "Illegal operation over an empty RLP stream")

proc getType*(self: Rlp): RlpNodeType =
  requireData()
  return if isBlob(): rlpBlob else: rlpList

proc lengthBytesCount(self: Rlp): int =
  var marker = bytes[position]
  if isBlob() and marker > LEN_PREFIXED_BLOB_MARKER:
    return int(marker - LEN_PREFIXED_BLOB_MARKER)
  if isList() and marker > LEN_PREFIXED_LIST_MARKER:
    return int(marker - LEN_PREFIXED_LIST_MARKER)
  return 0

proc isSingleByte(self: Rlp): bool =
  hasData() and bytes[position] < BLOB_START_MARKER

proc payloadOffset(self: Rlp): int =
  if isSingleByte(): 0 else: 1 + lengthBytesCount()

template readAheadCheck(numberOfBytes) =
  if position + numberOfBytes >= bytes.len: eosError()

template nonCanonicalNumberError =
  raise newException(MalformedRlpError, "Small number encoded in a non-canonical way")

proc payloadBytesCount(self: Rlp): int =
  if not hasData():
    return 0

  var marker = bytes[position]
  if marker < BLOB_START_MARKER:
    return 1
  if marker <= LEN_PREFIXED_BLOB_MARKER:
    result = int(marker - BLOB_START_MARKER)
    readAheadCheck(result)
    if result == 1:
      if bytes[position + 1] < BLOB_START_MARKER:
        nonCanonicalNumberError()
    return

  template readInt(startMarker, lenPrefixMarker) =
    var
      lengthBytes = int(marker - lenPrefixMarker)
      remainingBytes = self.bytes.len - self.position

    if remainingBytes <= lengthBytes:
      eosError()

    if remainingBytes > 1 and self.bytes[self.position + 1] == 0:
      raise newException(MalformedRlpError, "Number encoded with a leading zero")

    if lengthBytes > sizeof(result):
      raise newException(UnsupportedRlpError, "Message too large to fit in memory")

    for i in 1 .. lengthBytes:
      result = (result shl 8) or int(self.bytes[self.position + i])

    # must be greater than the short-list size list
    if result < THRESHOLD_LIST_LEN:
      nonCanonicalNumberError()

  if marker < LIST_START_MARKER:
    readInt(BLOB_START_MARKER, LEN_PREFIXED_BLOB_MARKER)
  elif marker <= LEN_PREFIXED_LIST_MARKER:
    result = int(marker - LIST_START_MARKER)
  else:
    readInt(LIST_START_MARKER, LEN_PREFIXED_LIST_MARKER)

  readAheadCheck(result)

proc blobLen*(self: Rlp): int =
  if isBlob(): payloadBytesCount() else: 0

proc isInt*(self: Rlp): bool =
  if not hasData():
    return false
  var marker = bytes[position]
  if marker < BLOB_START_MARKER:
    return marker != 0
  if marker == BLOB_START_MARKER:
    return true
  if marker <= LEN_PREFIXED_BLOB_MARKER:
    return bytes[position + 1] != 0
  if marker < LIST_START_MARKER:
    let offset = position + int(marker + 1 - LEN_PREFIXED_BLOB_MARKER)
    if offset >= bytes.len: eosError()
    return bytes[offset] != 0
  return false

template maxBytes*(o: typedesc[Ordinal | uint64 | uint]): int = sizeof(o)

proc toInt*(self: Rlp, IntType: typedesc): IntType =
  mixin maxBytes

  # XXX: self insertions are not working in generic procs
  # https://github.com/nim-lang/Nim/issues/5053
  if not self.hasData():
    raise newException(RlpTypeMismatch, "Attempt to read an Int value past the RLP end")

  if self.isList():
    raise newException(RlpTypeMismatch, "Int expected, but found a List")

  let
    payloadStart = self.payloadOffset()
    payloadSize = self.payloadBytesCount()

  if payloadSize > maxBytes(IntType):
    raise newException(RlpTypeMismatch, "The RLP contains a larger than expected Int value")

  for i in payloadStart ..< (payloadStart + payloadSize):
    result = cast[IntType](result shl 8) or cast[IntType](self.bytes[self.position + i])

proc toString*(self: Rlp): string =
  if not isBlob():
    raise newException(RlpTypeMismatch, "String expected, but the source RLP is not a blob")

  let
    payloadOffset = payloadOffset()
    payloadLen = payloadBytesCount()
    remainingBytes = bytes.len - position - payloadOffset

  if payloadLen > remainingBytes:
    eosError()

  result = newString(payloadLen)
  for i in 0 ..< payloadLen:
    # XXX: switch to copyMem here
    result[i] = char(bytes[position + payloadOffset + i])

proc toBytes*(self: Rlp): BytesRange =
  if not isBlob():
    raise newException(RlpTypeMismatch, "Bytes expected, but the source RLP in not a blob")

  let
    payloadOffset = payloadOffset()
    payloadLen = payloadBytesCount()
    ibegin = position + payloadOffset
    iend = ibegin + payloadLen - 1

  result = bytes.slice(ibegin, iend)

proc currentElemEnd(self: Rlp): int =
  result = position

  if not hasData():
    return

  if isSingleByte():
    result += 1
  elif isBlob() or isList():
    result += payloadOffset() + payloadBytesCount()

proc skipElem*(rlp: var Rlp) =
  rlp.position = rlp.currentElemEnd

iterator items*(self: var Rlp): var Rlp =
  assert isList()

  var
    payloadOffset = payloadOffset()
    payloadEnd = position + payloadOffset + payloadBytesCount()

  if payloadEnd > bytes.len:
    raise newException(MalformedRlpError, "List length extends past the end of the stream")

  position += payloadOffset

  while position < payloadEnd:
    let elemEnd = currentElemEnd()
    yield self
    position = elemEnd

proc listElem*(self: Rlp, i: int): Rlp =
  let payload = bytes.slice(position + payloadOffset())
  result = rlpFromBytes payload
  var pos = 0
  while pos < i and result.hasData:
    result.position = result.currentElemEnd()
    inc pos

proc listLen*(self: Rlp): int =
  if not isList():
    return 0

  var rlp = self
  for elem in rlp:
    inc result

proc readImpl(rlp: var Rlp, T: type string): string =
  result = rlp.toString
  rlp.skipElem

proc readImpl(rlp: var Rlp, T: type Integer): Integer =
  result = rlp.toInt(T)
  rlp.skipElem

proc readImpl(rlp: var Rlp, T: typedesc[enum]): T =
  result = type(result)(rlp.toInt(int))
  rlp.skipElem

proc readImpl[R, E](rlp: var Rlp, T: type array[R, E]): T =
  mixin read

  when E is (byte or char):
    if not rlp.isBlob:
      raise newException(RlpTypeMismatch, "Bytes array expected, but the source RLP is not a blob.")

    var bytes = rlp.toBytes
    if result.len != bytes.len:
      raise newException(RlpTypeMismatch, "Fixed-size array expected, but the source RLP contains a blob of different lenght")

    copyMem(addr result[0], bytes.baseAddr, bytes.len)

    rlp.skipElem

  else:
    if not rlp.isList:
      raise newException(RlpTypeMismatch, "List expected, but the source RLP is not a list.")

    if result.len != rlp.listLen:
      raise newException(RlpTypeMismatch, "Fixed-size array expected, but the source RLP contains a list of different length")

    var i = 0
    for elem in rlp:
      result[i] = rlp.read(E)
      inc i

proc readImpl[E](rlp: var Rlp, T: type seq[E]): T =
  mixin read

  when E is (byte or char):
    var bytes = rlp.toBytes
    result = newSeq[byte](bytes.len)
    copyMem(addr result[0], bytes.baseAddr, bytes.len)
    rlp.skipElem
  else:
    if not rlp.isList:
      raise newException(RlpTypeMismatch, "Sequence expected, but the source RLP is not a list.")

    result = newSeqOfCap[E](rlp.listLen)

    for elem in rlp:
      result.add rlp.read(E)

proc readImpl[E](rlp: var Rlp, T: type openarray[E]): seq[E] =
  result = readImpl(rlp, seq[E])

proc readImpl(rlp: var Rlp, T: typedesc[object|tuple],
              wrappedInList = wrapObjectsInList): T =
  mixin enumerateRlpFields, read

  if wrappedInList:
    var
      payloadOffset = rlp.payloadOffset()
      payloadEnd = rlp.position + payloadOffset + rlp.payloadBytesCount()

    rlp.position += payloadOffset

  template op(field) =
    field = rlp.read(type(field))

  enumerateRlpFields(result, op)

proc toNodes*(self: var Rlp): RlpNode =
  requireData()

  if isList():
    result.kind = rlpList
    newSeq result.elems, 0
    for e in self:
      result.elems.add e.toNodes
  else:
    assert isBlob()
    result.kind = rlpBlob
    result.bytes = toBytes()
    position = currentElemEnd()

# We define a single `read` template with a pretty low specifity
# score in order to facilitate easier overloading with user types:
template read*(rlp: var Rlp, T: typedesc): auto =
  readImpl(rlp, T)

proc decode*(bytes: openarray[byte]): RlpNode =
  var
    bytesCopy = @bytes
    rlp = rlpFromBytes(bytesCopy.toRange())
  return rlp.toNodes

template decode*(bytes: BytesRange, T: typedesc): untyped =
  mixin read
  var rlp = rlpFromBytes bytes
  rlp.read(T)

template decode*(bytes: openarray[byte], T: typedesc): T =
  var bytesCopy = @bytes
  decode(initBytesRange(bytesCopy), T)

proc append*(writer: var RlpWriter; rlp: Rlp) =
  append(writer, rlp.rawData)

proc isPrintable(s: string): bool =
  for c in s:
    if ord(c) < 32 or ord(c) >= 128:
      return false

  return true

proc inspectAux(self: var Rlp, depth: int, output: var string) =
  if not hasData():
    return

  template indent =
    for i in 0..<depth:
      output.add "  "

  indent()

  if self.isSingleByte:
    output.add "byte "
    output.add $bytes[position]
  elif self.isBlob:
    let str = self.toString
    if str.isPrintable:
      output.add '"'
      output.add str
      output.add '"'
    else:
      output.add "blob(" & $str.len & ") ["
      for c in str:
        output.add $ord(c)
        output.add ","
      output[^1] = ']'
  else:
    output.add "{\n"
    for subitem in self:
      inspectAux(subitem, depth + 1, output)
      output.add "\n"
    indent()
    output.add "}"

proc inspect*(self: Rlp, indent = 0): string =
  var rlpCopy = self
  result = newStringOfCap(bytes.len)
  inspectAux(rlpCopy, indent, result)

