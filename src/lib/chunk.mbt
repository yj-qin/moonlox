///|
struct Chunk {
  code : Array[Byte]
  lines : Array[Int]
  constants : ValueArray
  mut count : Int
} derive(Show)

///|
pub fn Chunk::new() -> Chunk {
  { code: [], lines: [], constants: ValueArray::new(), count: 0 }
}

///|
pub fn write(self : Chunk, code : Byte, line : Int) -> Unit {
  self.code.push(code)
  self.add_line(line, self.code.length() - 1)
  self.count += 1
}

///|
pub fn add_constant(self : Chunk, value : Value) -> Int {
  self.constants.add_value(value)
  self.constants.values.length() - 1
}

///|
fn add_line(self : Chunk, line : Int, offset : Int) -> Unit {
  let len = self.lines.length()
  if len == 0 || self.lines[len - 2] != line {
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
    buf.write_char('\n')
  }
  buf.to_string()
}

///|
fn disassemble_instruction(
  self : Chunk,
  buf : StringBuilder,
  offset : Int
) -> Int {
  buf.write_string(padding_prefix(offset.to_string(), 4, content="0") + " ")
  if offset > 0 && self.get_line(offset) == self.get_line(offset - 1) {
    buf.write_string("   | ")
  } else {
    buf.write_string(padding_prefix(self.get_line(offset).to_string(), 4) + " ")
  }
  let op = self.code[offset]
  match op {
    OP_NOP => simple_instruction(buf, "OP_NOP", offset)
    OP_RETURN => simple_instruction(buf, "OP_RETURN", offset)
    OP_PRINT => simple_instruction(buf, "OP_PRINT", offset)
    OP_POP => simple_instruction(buf, "OP_POP", offset)
    OP_DEFINE_GLOBAL =>
      self.constant_instruction(buf, "OP_DEFINE_GLOBAL", offset)
    OP_GET_GLOBAL => self.constant_instruction(buf, "OP_GET_GLOBAL", offset)
    OP_SET_GLOBAL => self.constant_instruction(buf, "OP_SET_GLOBAL", offset)
    OP_GET_LOCAL => self.byte_instruction(buf, "OP_GET_LOCAL", offset)
    OP_SET_LOCAL => self.byte_instruction(buf, "OP_SET_LOCAL", offset)
    OP_GET_UPVALUE => self.byte_instruction(buf, "OP_GET_UPVALUE", offset)
    OP_SET_UPVALUE => self.byte_instruction(buf, "OP_SET_UPVALUE", offset)
    OP_GET_PROPERTY => self.constant_instruction(buf, "OP_GET_PROPERTY", offset)
    OP_SET_PROPERTY => self.constant_instruction(buf, "OP_SET_PROPERTY", offset)
    OP_GET_SUPER => self.constant_instruction(buf, "OP_GET_SUPER", offset)
    OP_JUMP => self.jump_instruction(buf, 1, "OP_JUMP", offset)
    OP_JUMP_IF_FALSE =>
      self.jump_instruction(buf, 1, "OP_JUMP_IF_FALSE", offset)
    OP_LOOP => self.jump_instruction(buf, -1, "OP_LOOP", offset)
    OP_CALL => self.byte_instruction(buf, "OP_CALL", offset)
    OP_CLOSURE => self.closure_instruction(buf, "OP_CLOSURE", offset)
    OP_CLOSE_UPVALUE => simple_instruction(buf, "OP_CLOSE_UPVALUE", offset)
    OP_CLASS => self.constant_instruction(buf, "OP_CLASS", offset)
    OP_METHOD => self.constant_instruction(buf, "OP_METHOD", offset)
    OP_INVOKE => self.invoke_instruction(buf, "OP_INVOKE", offset)
    OP_SUPER_INVOKE => self.invoke_instruction(buf, "OP_SUPER_INVOKE", offset)
    OP_INHERIT => simple_instruction(buf, "OP_INHERIT", offset)
    OP_CONSTANT => self.constant_instruction(buf, "OP_CONSTANT", offset)
    OP_NIL => simple_instruction(buf, "OP_NIL", offset)
    OP_TRUE => simple_instruction(buf, "OP_TRUE", offset)
    OP_FALSE => simple_instruction(buf, "OP_FALSE", offset)
    OP_NEGATE => simple_instruction(buf, "OP_NEGATE", offset)
    OP_NOT => simple_instruction(buf, "OP_NOT", offset)
    OP_EQUAL => simple_instruction(buf, "OP_EQUAL", offset)
    OP_GREATER => simple_instruction(buf, "OP_GREATER", offset)
    OP_LESS => simple_instruction(buf, "OP_LESS", offset)
    OP_ADD => simple_instruction(buf, "OP_ADD", offset)
    OP_SUBTRACT => simple_instruction(buf, "OP_SUBTRACT", offset)
    OP_MULTIPLY => simple_instruction(buf, "OP_MULTIPLY", offset)
    OP_DIVIDE => simple_instruction(buf, "OP_DIVIDE", offset)
    OP_MOD => simple_instruction(buf, "OP_MOD", offset)
    _ => {
      buf.write_string("Unknown opcode \{op}")
      offset + 1
    }
  }
}

///|
fn simple_instruction(buf : StringBuilder, name : String, offset : Int) -> Int {
  let name = padding_postfix(name, 16)
  buf.write_string("\{name}")
  offset + 1
}

///|
fn constant_instruction(
  self : Chunk,
  buf : StringBuilder,
  name : String,
  offset : Int
) -> Int {
  let name = padding_postfix(name, 16)
  let constant = self.code[offset + 1].to_int()
  let constant_str = padding_prefix(constant.to_string(), 4, content="0")
  buf.write_string(
    "\{name} \{constant_str} '\{self.constants.values[constant]}'",
  )
  offset + 2
}

///|
fn closure_instruction(
  self : Chunk,
  buf : StringBuilder,
  name : String,
  offset : Int
) -> Int {
  let mut offset = offset + 1
  let name = padding_postfix(name, 16)
  let constant = self.code[offset].to_int()
  offset += 1
  let constant_str = padding_prefix(constant.to_string(), 4, content="0")
  buf.write_string(
    "\{name} \{constant_str} '\{self.constants.values[constant]}'",
  )
  guard let FunctionVal(function) = self.constants.values[constant]
  for i = 0; i < function.upvalue_count; i = i + 1 {
    buf.write_char('\n')
    let is_local = if self.code[offset] == 0 { "local" } else { "upvalue" }
    let index = self.code[offset + 1].to_int()
    let offset_str = padding_prefix(offset.to_string(), 4, content="0")
    buf.write_string(
      "\{offset_str}      |                      \{is_local} \{index}",
    )
    offset += 2
  }
  offset
}

///|
fn byte_instruction(
  self : Chunk,
  buf : StringBuilder,
  name : String,
  offset : Int
) -> Int {
  let name = padding_postfix(name, 16)
  let slot = self.code[offset + 1].to_int()
  let slot_str = padding_prefix(slot.to_string(), 4, content="0")
  buf.write_string("\{name} \{slot_str}")
  offset + 2
}

///|
fn jump_instruction(
  self : Chunk,
  buf : StringBuilder,
  sign : Int,
  name : String,
  offset : Int
) -> Int {
  let name = padding_postfix(name, 16)
  let offset_str = padding_prefix(offset.to_string(), 4, content="0")
  let mut jump = (self.code[offset + 1] << 8).to_int()
  jump = jump | self.code[offset + 2].to_int()
  buf.write_string("\{name} \{offset_str} -> \{offset + 3 + sign * jump}")
  offset + 3
}

///|
fn invoke_instruction(
  self : Chunk,
  buf : StringBuilder,
  name : String,
  offset : Int
) -> Int {
  let constant = self.code[offset + 1].to_int()
  let arg_count = self.code[offset + 2].to_int()
  let name = padding_postfix(name, 16)
  let constant_str = padding_prefix(constant.to_string(), 4, content="0")
  buf.write_string(
    "\{name} (\{arg_count} args) \{constant_str} '\{self.constants.values[constant]}'",
  )
  offset + 3
}
