import macros

template enumerateRlpFields*[T](x: T, op: untyped) =
  for f in fields(x): op(f)

macro rlpFields*(T: typedesc, fields: varargs[untyped]): untyped =
  var body = newStmtList()
  let
    ins = genSym(nskParam, "instance")
    op = genSym(nskParam, "op")

  for field in fields:
    body.add quote do: `op`(`ins`.`field`)

  result = quote do:
    template enumerateRlpFields*(`ins`: `T`, `op`: untyped) {.inject.} =
      `body`
