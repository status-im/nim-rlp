import
  macros, types,
  ranges/[memranges, ptr_arith],
  object_serialization, priv/defs

export
  memranges

type
  RlpWriter* = object
    pendingLists: seq[tuple[remainingItems, outBytes: int]]
    output: Bytes

  PrematureFinalizationError* = object of Exception

  IntLike* = concept x, y
    x + y
    x * y
    x - y
    x div y
    x mod y
    x shr y
    x shl y
    x and int # for masking

  # Integer* = SomeOrdinal or IntLike
  Integer = int

proc bytesNeeded(num: Integer): int =
  var n = num
  while n != 0:
    inc result
    n = n shr 8

proc writeBigEndian(outStream: var Bytes, number: int,
                    lastByteIdx: int, numberOfBytes: int) =
  var n = number
  for i in countdown(lastByteIdx, lastByteIdx - int(numberOfBytes) + 1):
    outStream[i] = byte(n and 0xff)
    n = n shr 8

proc writeBigEndian(outStream: var Bytes, number: int,
                    numberOfBytes: int) {.inline.} =
  outStream.setLen(outStream.len + numberOfBytes)
  outStream.writeBigEndian(number, outStream.len - 1, numberOfBytes)

proc writeCount(bytes: var Bytes, count: int, baseMarker: byte) =
  if count < THRESHOLD_LIST_LEN:
    bytes.add(baseMarker + byte(count))
  else:
    let
      origLen = bytes.len
      lenPrefixBytes = count.bytesNeeded

    bytes.setLen(origLen + int(lenPrefixBytes) + 1)
    bytes[origLen] = baseMarker + (THRESHOLD_LIST_LEN - 1) + byte(lenPrefixBytes)
    bytes.writeBigEndian(count, bytes.len - 1, lenPrefixBytes)

proc add(outStream: var Bytes, newChunk: BytesRange) =
  let prevLen = outStream.len
  outStream.setLen(prevLen + newChunk.len)
  # XXX: Use copyMem here
  for i in 0 ..< newChunk.len:
    outStream[prevLen + i] = newChunk[i]

{.this: self.}
{.experimental.}

using
  self: var RlpWriter

proc initRlpWriter*: RlpWriter =
  newSeq(result.pendingLists, 0)
  newSeq(result.output, 0)

proc decRet(n: var int, delta: int): int =
  n -= delta
  return n

proc maybeClosePendingLists(self) =
  while pendingLists.len > 0:
    let lastListIdx = pendingLists.len - 1
    assert pendingLists[lastListIdx].remainingItems >= 1
    if decRet(pendingLists[lastListIdx].remainingItems, 1) == 0:
      # A list have been just finished. It was started in `startList`.
      let listStartPos = pendingLists[lastListIdx].outBytes
      pendingLists.setLen lastListIdx

      # How many bytes were written since the start?
      let listLen = output.len - listStartPos

      # Compute the number of bytes required to write down the list length
      let totalPrefixBytes = if listLen < int(THRESHOLD_LIST_LEN): 1
                             else: int(listLen.bytesNeeded) + 1

      # Shift the written data to make room for the prefix length
      output.setLen(output.len + totalPrefixBytes)
      let outputBaseAddr = output.baseAddr

      moveMem(outputBaseAddr.shift(listStartPos + totalPrefixBytes),
              outputBaseAddr.shift(listStartPos),
              listLen)

      # Write out the prefix length
      if listLen < THRESHOLD_LIST_LEN:
        output[listStartPos] = LIST_START_MARKER + byte(listLen)
      else:
        let listLenBytes = totalPrefixBytes - 1
        output[listStartPos] = LEN_PREFIXED_LIST_MARKER + byte(listLenBytes)
        output.writeBigEndian(listLen, listStartPos + listLenBytes, listLenBytes)
    else:
      # The currently open list is not finished yet. Nothing to do.
      return

proc appendRawList(self; bytes: BytesRange) =
  output.writeCount(bytes.len, LIST_START_MARKER)
  output.add(bytes)
  maybeClosePendingLists()

proc startList(self; listSize: int) =
  if listSize == 0:
    appendRawList zeroBytesRange
  else:
    pendingLists.add((listSize, output.len))

template appendImpl(self; data, startMarker) =
  mixin baseAddr

  if data.len == 1 and byte(data[0]) < BLOB_START_MARKER:
    self.output.add byte(data[0])
  else:
    self.output.writeCount(data.len, startMarker)

    let startPos = output.len
    self.output.setLen(startPos + data.len)
    copyMem(shift(baseAddr(self.output), startPos),
            baseAddr(data),
            data.len)

  maybeClosePendingLists()

proc append*(self; data: string) =
  appendImpl(self, data, BLOB_START_MARKER)

proc append*(self; data: Bytes) =
  appendImpl(self, data, BLOB_START_MARKER)

proc append*(self; data: BytesRange) =
  appendImpl(self, data, BLOB_START_MARKER)

proc append*(self; data: MemRange) =
  appendImpl(self, data, BLOB_START_MARKER)

proc append*(self; i: Integer) =
  if i == 0:
    self.output.add BLOB_START_MARKER
  elif i < Integer(BLOB_START_MARKER):
    self.output.add byte(i)
  else:
    let bytesNeeded = i.bytesNeeded
    self.output.writeCount(bytesNeeded, BLOB_START_MARKER)
    self.output.writeBigEndian(i.int, bytesNeeded)

  self.maybeClosePendingLists()

proc append*[T](self; list: openarray[T]) =
  self.startList list.len
  for i in 0 ..< list.len:
    self.append list[i]

proc append*[T](self; list: seq[T]) =
  self.startList list.len
  for i in 0 ..< list.len:
    self.append list[i]

proc append*(self; data: object|tuple) =
  mixin enumerateRlpFields, append
  template op(x) = append(self, x)
  enumerateRlpFields(data, op)

proc initRlpList*(listSize: int): RlpWriter =
  result = initRlpWriter()
  startList(result, listSize)

proc finish*(self): BytesRange =
  if pendingLists.len > 0:
    raise newException(PrematureFinalizationError,
      "Insufficient number of elements written to a started list")
  result = initBytesRange(output)

proc encode*[T](v: T): BytesRange =
  var writer = initRlpWriter()
  writer.append(v)
  return writer.finish

macro encodeList*(args: varargs[untyped]): BytesRange =
  var
    listLen = args.len
    writer = genSym(nskVar, "rlpWriter")
    body = newStmtList()

  for arg in args:
    body.add quote do:
      append(`writer`, `arg`)

  result = quote do:
    var `writer` = initRlpList(`listLen`)
    `body`
    finish(`writer`)

when false:
  # XXX: Currently fails with a malformed AST error on the args.len expression
  template encodeList*(args: varargs[untyped]): BytesRange =
    var writer = initRlpList(args.len)
    for arg in args:
      writer.append(arg)
    writer.finish

