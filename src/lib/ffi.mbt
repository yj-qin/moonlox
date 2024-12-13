///|
fn __read_char() -> Int = "__moonbit_io_unstable" "read_char"

///|
fn __now() -> UInt64 = "__moonbit_time_unstable" "now"

///|
pub fn read_char() -> Char? {
  Some(Char::from_int(__read_char()))
}

///|
pub fn read_line_from_stdin() -> String? {
  let buf = StringBuilder::new()
  while true {
    let c = read_char()
    match c {
      None => return None
      Some('\n') => {
        buf.write_char('\n')
        break
      }
      Some(c) => buf.write_char(c)
    }
  }
  Some(buf.to_string())
}

///|
pub fn now() -> UInt64 {
  __now()
}
