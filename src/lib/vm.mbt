///| Max stack size
const STACK_MAX = 256

///|
pub(readonly) enum InterpretResult {
  OK
  CompileError
  RuntimeError
} derive(Show)

///|
struct VM {
  mut chunk : Chunk?
  mut ip : Int
  stack : FixedArray[Value]
  mut sp : Int
  debug : Bool
}

///|
pub fn VM::new(debug~ : Bool = false) -> VM {
  {
    chunk: None,
    ip: 0,
    stack: FixedArray::makei(STACK_MAX, fn(_i) { 0 }),
    sp: 0,
    debug,
  }
}

///|
pub fn interpret(self : VM, source : String) -> InterpretResult {
  let compiler = Compiler::new(source, debug=self.debug)
  match compiler.compile() {
    Ok(chunk) => {
      self.chunk = Some(chunk)
      self.ip = 0
    }
    Err(_) => return CompileError
  }
  self.run()
}

///|
fn run(self : VM) -> InterpretResult {
  let chunk = self.chunk.unwrap()
  let debug_buf = StringBuilder::new()
  for {
    if self.debug {
      debug_buf.reset()
      // print stack
      debug_buf.write_string("          ")
      for i = 0; i < self.sp; i = i + 1 {
        debug_buf.write_string("[ ")
        debug_buf.write_string(self.stack[i].to_string())
        debug_buf.write_string(" ]")
      }
      debug_buf.write_char('\n')
      // print instruction
      let _ = chunk.disassemble_instruction(debug_buf, self.ip)
      println(debug_buf)
    }
    let instruction = chunk.code[self.ip]
    self.ip += 1
    match instruction {
      OP_NOP => continue
      OP_CONSTANT => {
        let constant_idx = chunk.code[self.ip].to_int()
        self.ip += 1
        let constant = chunk.constants.values[constant_idx]
        self.push(constant)
      }
      OP_NEGATE => self.stack[self.sp - 1] = -self.stack[self.sp - 1]
      OP_ADD => {
        let b = self.pop()
        let a = self.pop()
        self.push(a + b)
      }
      OP_SUBTRACT => {
        let b = self.pop()
        let a = self.pop()
        self.push(a - b)
      }
      OP_MULTIPLY => {
        let b = self.pop()
        let a = self.pop()
        self.push(a * b)
      }
      OP_DIVIDE => {
        let b = self.pop()
        let a = self.pop()
        self.push(a / b)
      }
      OP_RETURN => {
        println("\{self.pop()}")
        return OK
      }
      _ => return RuntimeError
    }
  }
}

///|
fn push(self : VM, value : Value) -> Unit {
  self.stack[self.sp] = value
  self.sp += 1
}

///|
fn pop(self : VM) -> Value {
  self.sp -= 1
  self.stack[self.sp]
}
