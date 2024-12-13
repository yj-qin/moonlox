///| Max call frame count
const FRAMES_MAX = 64

///| Max stack size (FRAMES_MAX * UINT8_COUNT)
const STACK_MAX = 16384

///|
struct CallFrame {
  closure : Closure
  mut ip : Int
  slot : Int
}

///|
pub enum InterpretResult {
  OK
  CompileError
  RuntimeError
} derive(Show)

///|
struct VM {
  frames : FixedArray[CallFrame?]
  mut frame_count : Int
  stack : FixedArray[Value]
  mut sp : Int
  globals : Map[String, Value]
  mut open_upvals : Upval?
  init_string : String
  debug : Bool
}

///|
pub fn VM::new(debug~ : Bool = false) -> VM {
  let vm = {
    frames: FixedArray::makei(STACK_MAX, fn(_i) { None }),
    frame_count: 0,
    stack: FixedArray::makei(STACK_MAX, fn(_i) { NilVal }),
    sp: 0,
    globals: {},
    open_upvals: None,
    init_string: "init",
    debug,
  }
  vm.define_native("clock", 0, clock_native)
  vm
}

///|
pub fn interpret(self : VM, source : String) -> InterpretResult {
  let compiler = Compiler::new(source, debug=self.debug)
  let function = match compiler.compile() {
    Ok(f) => f
    Err(_) => return CompileError
  }
  let closure = Closure::new(function)
  self.push(ClosureVal(closure))
  ignore(self.call_closure(closure, 0))
  self.run()
}

///|
fn run(self : VM) -> InterpretResult {
  let mut frame = self.frames[self.frame_count - 1].unwrap()
  let debug_buf = StringBuilder::new()
  if self.debug {
    println("== run ==")
  }
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
      let _ = frame.closure.function.chunk.disassemble_instruction(
        debug_buf,
        frame.ip,
      )
      println(debug_buf)
    }
    let instruction = frame.closure.function.chunk.code[frame.ip]
    frame.ip += 1
    match instruction {
      OP_NOP => continue
      OP_RETURN => {
        // Exit interpreter
        let result = self.pop()
        self.close_upvalues(frame.slot)
        self.frame_count -= 1
        if self.frame_count == 0 {
          ignore(self.pop())
          return OK
        }
        self.sp = frame.slot
        self.push(result)
        frame = self.frames[self.frame_count - 1].unwrap()
      }
      OP_PRINT => println("\{self.pop()}")
      OP_POP => self.sp -= 1
      OP_DEFINE_GLOBAL => {
        guard let StringVal(name) = self.read_constant()
        self.globals.set(name, self.peek(0))
        self.sp -= 1
      }
      OP_GET_GLOBAL => {
        guard let StringVal(name) = self.read_constant()
        let value = if self.globals.contains(name) {
          self.globals[name].unwrap()
        } else {
          self.runtime_error("Undefined variable '\{name}'")
          return RuntimeError
        }
        self.push(value)
      }
      OP_SET_GLOBAL => {
        guard let StringVal(name) = self.read_constant()
        if self.globals.contains(name) {
          self.globals.set(name, self.peek(0))
        } else {
          self.runtime_error("Undefined variable '\{name}'")
          return RuntimeError
        }
      }
      OP_GET_LOCAL => {
        let offset = self.read_byte()
        self.push(self.stack[frame.slot + offset])
      }
      OP_SET_LOCAL => {
        let offset = self.read_byte()
        self.stack[frame.slot + offset] = self.peek(0)
      }
      OP_GET_UPVALUE => {
        let slot = self.read_byte()
        let upval = frame.closure.upvalues[slot].unwrap()
        let location = upval.location
        if location == -1 {
          self.push(upval.closed)
        } else {
          self.push(self.stack[location])
        }
      }
      OP_SET_UPVALUE => {
        let slot = self.read_byte()
        let upval = frame.closure.upvalues[slot].unwrap()
        let location = upval.location
        if location == -1 {
          upval.closed = self.peek(0)
        } else {
          self.stack[location] = self.peek(0)
        }
      }
      OP_GET_PROPERTY => {
        let instance = match self.peek(0) {
          InstanceVal(i) => i
          _ => {
            self.runtime_error("Only instances have properties.")
            return RuntimeError
          }
        }
        guard let StringVal(name) = self.read_constant()
        match instance.fields[name] {
          Some(value) => {
            self.sp -= 1 // instance 
            self.push(value)
          }
          None =>
            if not(self.bind_mthd(instance.class, name)) {
              return RuntimeError
            }
        }
      }
      OP_SET_PROPERTY => {
        let instance = match self.peek(1) {
          InstanceVal(i) => i
          _ => {
            self.runtime_error("Only instances have properties.")
            return RuntimeError
          }
        }
        guard let StringVal(field) = self.read_constant()
        instance.fields.set(field, self.peek(0))
        let value = self.pop()
        self.sp -= 1
        self.push(value)
      }
      OP_GET_SUPER => {
        guard let StringVal(name) = self.read_constant()
        guard let ClassVal(superclass) = self.pop()
        if not(self.bind_mthd(superclass, name)) {
          return RuntimeError
        }
      }
      OP_JUMP_IF_FALSE => {
        let offset = self.read_short()
        if self.peek(0).is_falsey() {
          frame.ip += offset
        }
      }
      OP_JUMP => {
        let offset = self.read_short()
        frame.ip += offset
      }
      OP_LOOP => {
        let offset = self.read_short()
        frame.ip -= offset
      }
      OP_CALL => {
        let arg_count = self.read_byte()
        if not(self.call_value(self.peek(arg_count), arg_count)) {
          return RuntimeError
        }
        frame = self.frames[self.frame_count - 1].unwrap()
      }
      OP_CLOSURE => {
        guard let FunctionVal(function) = self.read_constant()
        let closure = Closure::new(function)
        self.push(ClosureVal(closure))
        for i = 0; i < closure.upvalue_count; i = i + 1 {
          let is_local = self.read_byte()
          let index = self.read_byte()
          closure.upvalues[i] = if is_local == 1 {
            Some(self.capture_upvalue(frame.slot + index))
          } else {
            frame.closure.upvalues[index]
          }
        }
      }
      OP_CLOSE_UPVALUE => {
        self.close_upvalues(self.sp - 1)
        self.sp -= 1
      }
      OP_CLASS => {
        guard let StringVal(name) = self.read_constant()
        self.push(ClassVal(Class::new(name)))
      }
      OP_METHOD => {
        guard let StringVal(name) = self.read_constant()
        self.define_method(name)
      }
      OP_INVOKE => {
        guard let StringVal(mthd) = self.read_constant()
        let arg_count = self.read_byte()
        if not(self.invoke(mthd, arg_count)) {
          return RuntimeError
        }
        frame = self.frames[self.frame_count - 1].unwrap()
      }
      OP_SUPER_INVOKE => {
        guard let StringVal(mthd) = self.read_constant()
        let arg_count = self.read_byte()
        guard let ClassVal(superclass) = self.pop()
        if not(self.invoke_from_class(superclass, mthd, arg_count)) {
          return RuntimeError
        }
        frame = self.frames[self.frame_count - 1].unwrap()
      }
      OP_INHERIT => {
        let superclass = match self.peek(1) {
          ClassVal(c) => c
          _ => {
            self.runtime_error("Superclass must be a class.")
            return RuntimeError
          }
        }
        guard let ClassVal(subclass) = self.peek(0)
        for k, v in superclass.methods {
          subclass.methods[k] = v
        }
        self.sp -= 1 // subclass
      }
      OP_CONSTANT => self.push(self.read_constant())
      OP_NIL => self.push(NilVal)
      OP_TRUE => self.push(BoolVal(true))
      OP_FALSE => self.push(BoolVal(false))
      OP_NEGATE =>
        match self.peek(0) {
          NumberVal(n) => {
            self.sp -= 1
            self.push(NumberVal(-n))
          }
          _ => {
            self.runtime_error("Operand must be a number.")
            return RuntimeError
          }
        }
      OP_NOT => self.push(BoolVal(self.pop().is_falsey()))
      OP_EQUAL => {
        let b = self.pop()
        let a = self.pop()
        self.push(BoolVal(a == b))
      }
      OP_GREATER =>
        match (self.peek(0), self.peek(1)) {
          (NumberVal(b), NumberVal(a)) => {
            self.sp -= 2
            self.push(BoolVal(a > b))
          }
          _ => {
            self.runtime_error("Operands must be numbers.")
            return RuntimeError
          }
        }
      OP_LESS =>
        match (self.peek(0), self.peek(1)) {
          (NumberVal(b), NumberVal(a)) => {
            self.sp -= 2
            self.push(BoolVal(a < b))
          }
          _ => {
            self.runtime_error("Operands must be numbers.")
            return RuntimeError
          }
        }
      OP_ADD =>
        match (self.peek(0), self.peek(1)) {
          (StringVal(b), StringVal(a)) => {
            self.sp -= 2
            self.push(StringVal(a + b))
          }
          (NumberVal(b), NumberVal(a)) => {
            self.sp -= 2
            self.push(NumberVal(a + b))
          }
          _ => {
            self.runtime_error("Operands must be two numbers or two strings.")
            return RuntimeError
          }
        }
      OP_SUBTRACT =>
        match (self.peek(0), self.peek(1)) {
          (NumberVal(b), NumberVal(a)) => {
            self.sp -= 2
            self.push(NumberVal(a - b))
          }
          _ => {
            self.runtime_error("Operands must be numbers.")
            return RuntimeError
          }
        }
      OP_MULTIPLY =>
        match (self.peek(0), self.peek(1)) {
          (NumberVal(b), NumberVal(a)) => {
            self.sp -= 2
            self.push(NumberVal(a * b))
          }
          _ => {
            self.runtime_error("Operands must be numbers.")
            return RuntimeError
          }
        }
      OP_DIVIDE =>
        match (self.peek(0), self.peek(1)) {
          (NumberVal(b), NumberVal(a)) => {
            self.sp -= 2
            self.push(NumberVal(a / b))
          }
          _ => {
            self.runtime_error("Operands must be numbers.")
            return RuntimeError
          }
        }
      OP_MOD =>
        match (self.peek(0), self.peek(1)) {
          (NumberVal(b), NumberVal(a)) => {
            self.sp -= 2
            self.push(NumberVal(a % b))
          }
          _ => {
            self.runtime_error("Operands must be numbers.")
            return RuntimeError
          }
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

///|
fn peek(self : VM, distance : Int) -> Value {
  self.stack[self.sp - 1 - distance]
}

///|
fn call_closure(self : VM, closure : Closure, arg_count : Int) -> Bool {
  if arg_count != closure.function.arity {
    self.runtime_error(
      "Expect \{closure.function.arity} arguments but got \{arg_count}",
    )
    return false
  }
  if self.frame_count == FRAMES_MAX {
    self.runtime_error("Stack overflow.")
    return false
  }
  let frame = { closure, ip: 0, slot: self.sp - arg_count - 1 }
  self.frames[self.frame_count] = Some(frame)
  self.frame_count += 1
  true
}

///|
fn call_value(self : VM, callee : Value, arg_count : Int) -> Bool {
  match callee {
    BoundMethodVal(bound) => {
      self.stack[self.sp - arg_count - 1] = bound.receiver
      self.call_closure(bound.mthd, arg_count)
    }
    ClassVal(class) => {
      self.stack[self.sp - arg_count - 1] = InstanceVal(Instance::new(class))
      match class.methods[self.init_string] {
        Some(ClosureVal(initializer)) =>
          return self.call_closure(initializer, arg_count)
        _ =>
          if arg_count != 0 {
            self.runtime_error("Expect 0 arguments but got \{arg_count}")
            return false
          }
      }
      true
    }
    ClosureVal(cls) => self.call_closure(cls, arg_count)
    NativeFunctionVal(f) => {
      if arg_count != f.arity {
        self.runtime_error("Expect \{f.arity} arguments but got \{arg_count}")
        return false
      }
      let args = FixedArray::makei(arg_count, fn(_i) { Value::NilVal })
      self.stack.blit_to(args, len=arg_count, src_offset=self.sp - arg_count)
      let result = (f.function)(arg_count, args)
      self.sp -= arg_count + 1
      self.push(result)
      true
    }
    _ => {
      self.runtime_error("Can only call functions and classes.")
      false
    }
  }
}

///|
fn invoke(self : VM, name : String, arg_count : Int) -> Bool {
  let instance = match self.peek(arg_count) {
    InstanceVal(i) => i
    _ => {
      self.runtime_error("Only instances have methods.")
      return false
    }
  }
  match instance.fields[name] {
    Some(value) => {
      self.stack[self.sp - arg_count - 1] = value
      self.call_value(value, arg_count)
    }
    _ => self.invoke_from_class(instance.class, name, arg_count)
  }
}

///|
fn invoke_from_class(
  self : VM,
  class : Class,
  name : String,
  arg_count : Int
) -> Bool {
  match class.methods[name] {
    Some(ClosureVal(mthd)) => self.call_closure(mthd, arg_count)
    _ => {
      self.runtime_error("Undefined property '\{name}'")
      false
    }
  }
}

///|
fn bind_mthd(self : VM, class : Class, name : String) -> Bool {
  let mthd_val = match class.methods[name] {
    Some(m) => m
    None => {
      self.runtime_error("Undefined property '\{name}'.")
      return false
    }
  }
  guard let ClosureVal(mthd) = mthd_val
  let bound = BoundMethod::new(self.peek(0), mthd)
  self.sp -= 1
  self.push(BoundMethodVal(bound))
  true
}

///|
fn capture_upvalue(self : VM, location : Int) -> Upval {
  let mut prev_upval = None
  let mut upval = self.open_upvals
  while not(upval.is_empty()) && upval.unwrap().location > location {
    prev_upval = upval
    upval = upval.unwrap().next
  }
  if not(upval.is_empty()) && upval.unwrap().location == location {
    return upval.unwrap()
  }
  let created_upval = { location, next: None, closed: NilVal }
  created_upval.next = upval
  if prev_upval.is_empty() {
    self.open_upvals = Some(created_upval)
  } else {
    prev_upval.unwrap().next = Some(created_upval)
  }
  created_upval
}

///|
fn close_upvalues(self : VM, last : Int) -> Unit {
  while not(self.open_upvals.is_empty()) &&
        self.open_upvals.unwrap().location >= last {
    let upval = self.open_upvals.unwrap()
    upval.closed = self.stack[upval.location]
    upval.location = -1
    self.open_upvals = upval.next
  }
}

///|
fn define_method(self : VM, name : String) -> Unit {
  let mthd = self.peek(0)
  guard let ClassVal(class) = self.peek(1)
  class.methods.set(name, mthd)
  self.sp -= 1
}

///|
fn current_frame(self : VM) -> CallFrame {
  self.frames[self.frame_count - 1].unwrap()
}

///|
fn read_byte(self : VM) -> Int {
  let frame = self.current_frame()
  let b = frame.closure.function.chunk.code[frame.ip].to_int()
  frame.ip += 1
  b
}

///|
fn read_short(self : VM) -> Int {
  let frame = self.current_frame()
  frame.ip += 2
  let code = frame.closure.function.chunk.code
  (code[frame.ip - 2] << 8).to_int() | code[frame.ip - 1].to_int()
}

///|
fn read_constant(self : VM) -> Value {
  let frame = self.current_frame()
  frame.closure.function.chunk.constants.values[self.read_byte()]
}

///|
fn runtime_error(self : VM, message : String) -> Unit {
  println(message)
  for i = self.frame_count - 1; i >= 0; i = i - 1 {
    let frame = self.frames[i].unwrap()
    let function = frame.closure.function
    let line = frame.closure.function.chunk.get_line(frame.ip)
    let name = if function.name == "" { "script" } else { "\{function.name}()" }
    println("[line \{line}] in \{name}")
  }
  self.reset_stack()
}

///|
fn define_native(
  self : VM,
  name : String,
  arity : Int,
  function : (Int, FixedArray[Value]) -> Value
) -> Unit {
  self.globals.set(name, NativeFunctionVal({ name, arity, function }))
}

///|
fn reset_stack(self : VM) -> Unit {
  self.frame_count = 0
}
