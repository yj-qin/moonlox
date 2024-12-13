///|
struct Chunk {
  code : Array[Byte]
  lines : Array[Int]
  constants : ValueArray
}

///|
pub fn Chunk::new() -> Chunk {
  { code: [], lines: [], constants: ValueArray::new() }
}

///|
pub fn write(self : Chunk, code : Byte, line : Int) -> Unit {
  self.code.push(code)
  self.add_line(line, self.code.length() - 1)
}

///|
pub fn add_constant(self : Chunk, value : Value) -> Int {
  self.constants.add_value(value)
  return self.constants.values.length() - 1
}

///|
fn add_line(self : Chunk, line : Int, offset : Int) -> Unit {
  let len = self.lines.length()
  if len == 0 || self.lines[len - 2] == line {
    self.lines.push(line)
    self.lines.push(offset)
  } else {
    self.lines[len - 1] = offset
  }
}

///|
fn get_line(self : Chunk, offset : Int) -> Int {
  for i = 0; i < self.lines.length(); i = i + 2 {
    if offset > self.lines[i + 1] {
      continue
    }
    return self.lines[i]
  }
  -1
}

///|
fn pprint(self : Chunk, name : String) -> String {
  let buf = StringBuilder::new()
  buf.write_string("== \{name} ==\n")
  let mut offset = 0
  while offset < self.code.length() {
    offset = self.disassemble_instruction(buf, offset)
  }
  buf.to_string()
}

///|
fn disassemble_instruction(
  self : Chunk,
  buf : StringBuilder,
  offset : Int
) -> Int {
  buf.write_string(padding_prefix(offset, 4, content="0") + " ")
  if offset > 0 && self.get_line(offset) == self.get_line(offset - 1) {
    buf.write_string("   | ")
  } else {
    buf.write_string(padding_prefix(self.get_line(offset), 4) + " ")
  }
  let op = self.code[offset]
  match op {
    OP_NOP => simple_instruction(buf, "OP_NOP", offset)
    OP_RETURN => simple_instruction(buf, "OP_RETURN", offset)
    OP_CONSTANT => self.constant_instruction(buf, "OP_CONSTANT", offset)
    OP_NEGATE => simple_instruction(buf, "OP_NEGATE", offset)
    OP_ADD => simple_instruction(buf, "OP_ADD", offset)
    OP_SUBTRACT => simple_instruction(buf, "OP_SUBTRACT", offset)
    OP_MULTIPLY => simple_instruction(buf, "OP_MULTIPLY", offset)
    OP_DIVIDE => simple_instruction(buf, "OP_DIVIDE", offset)
    _ => {
      buf.write_string("Unknown opcode \{op}\n")
      offset + 1
    }
  }
}

///|
fn simple_instruction(buf : StringBuilder, name : String, offset : Int) -> Int {
  buf.write_string("\{name}\n")
  offset + 1
}

///|
fn constant_instruction(
  self : Chunk,
  buf : StringBuilder,
  name : String,
  offset : Int
) -> Int {
  let constant = self.code[offset + 1].to_int()
  buf.write_string("\{name} \{constant} '\{self.constants.values[constant]}'\n")
  offset + 2
}

test "pprint" {
  let chunk = Chunk::new()
  let constant = chunk.add_constant(1.2)
  chunk.write(OP_NOP, 123)
  chunk.write(OP_CONSTANT, 123)
  chunk.write(constant.to_byte(), 123)
  chunk.write(OP_NEGATE, 123)
  chunk.write(OP_RETURN, 123)
  inspect!(
    chunk.pprint("test"),
    content=
      #|== test ==
      #|0000  123 OP_NOP
      #|0001    | OP_CONSTANT 0 '1.2'
      #|0003    | OP_NEGATE
      #|0004    | OP_RETURN
      #|
    ,
  )
}
