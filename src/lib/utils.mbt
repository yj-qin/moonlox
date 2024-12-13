///|
fn padding_prefix(str : String, count : Int, content~ : String = " ") -> String {
  let sb = StringBuilder::new()
  let len = str.length()
  if len < count {
    for i in 0..<(count - len) {
      sb.write_string(content)
    }
  }
  sb.write_string(str)
  sb.to_string()
}

///|
fn padding_postfix(
  str : String,
  count : Int,
  content~ : String = " "
) -> String {
  let sb = StringBuilder::new()
  let len = str.length()
  sb.write_string(str)
  if len < count {
    for i in 0..<(count - len) {
      sb.write_string(content)
    }
  }
  sb.to_string()
}

///|
fn is_digit(c : Char?) -> Bool {
  if c == None {
    return false
  }
  let c = c.unwrap()
  '0' <= c && c <= '9'
}

///|
fn is_alpha(c : Char?) -> Bool {
  if c == None {
    return false
  }
  let c = c.unwrap()
  ('a' <= c && c <= 'z') || ('A' <= c && c <= 'Z') || c == '_'
}
