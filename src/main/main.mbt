///|
const DEBUG_MODE = false

///|
fn main {
  let argv = @sys.get_cli_args()[1:]
  let argc = argv.length()
  match argc {
    0 => repl()
    1 => runFile(argv[0])
    _ => {
      println("Usage: moonlox [path]")
      @sys.exit(64)
    }
  }
}

///|
fn repl() -> Unit {
  let vm = @lib.VM::new(debug=DEBUG_MODE)
  println("REPL mode, press Ctrl + C to exit.")
  for {
    println(">> ")
    match @lib.read_line_from_stdin() {
      Some(line) => {
        let _ = vm.interpret(line)

      }
      None => {
        println("")
        break
      }
    }
  }
}

///|
fn runFile(path : String) -> Unit {
  let vm = @lib.VM::new(debug=DEBUG_MODE)
  let source = try {
    @fs.read_file_to_string(path)
  } catch {
    _ => abort("Read file error")
  }
  match vm.interpret(source) {
    CompileError => @sys.exit(65)
    RuntimeError => @sys.exit(70)
    OK => ()
  }
}
