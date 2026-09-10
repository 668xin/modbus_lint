// Value encoding: map PLC values (coils, 16/32-bit integers) onto the raw
// 16-bit words that travel on the Modbus wire, honouring byte order and word
// order. This is the layer a driver uses to translate a point-table register
// into the bytes sent to / received from the slave.
//
// Conventions
// -----------
// A "word" is a 16-bit value stored as an `Int` in 0..=65535.
// Byte order says which of a word's two bytes is transmitted first.
// Word order says which of a 32-bit value's two words occupies the lower
// register address.
//
// All arithmetic stays inside the 32-bit `Int` range, so the code behaves
// identically on every backend without depending on 64-bit-wide globals.

///|
/// How the two bytes of a 16-bit word are placed on the wire.
pub enum ByteOrder {
  /// Big endian: high byte transmitted first.
  BigEndian
  /// Little endian: low byte transmitted first.
  LittleEndian
}

///|
/// In which register the high word of a 32-bit value is mapped.
pub enum WordOrder {
  /// Native order: the high word occupies the lower register address.
  HighWordLowAddress
  /// Byte-swapped order: the low word occupies the lower register address.
  LowWordLowAddress
}

///|
/// The same value laid out according to the reverse of an order.
fn swap_byte_order(order : ByteOrder) -> ByteOrder {
  match order {
    BigEndian => LittleEndian
    LittleEndian => BigEndian
  }
}

///|
/// The reverse of a word order.
fn swap_word_order(order : WordOrder) -> WordOrder {
  match order {
    HighWordLowAddress => LowWordLowAddress
    LowWordLowAddress => HighWordLowAddress
  }
}

///|
/// Human keyword for a byte order, for reports and (de)serialization.
pub fn byte_order_name(order : ByteOrder) -> String {
  match order {
    BigEndian => "big-endian"
    LittleEndian => "little-endian"
  }
}

///|
/// Human keyword for a word order, for reports and (de)serialization.
pub fn word_order_name(order : WordOrder) -> String {
  match order {
    HighWordLowAddress => "hi-lo"
    LowWordLowAddress => "lo-hi"
  }
}

///|
/// The two bytes (ints in 0..=255) of a 16-bit word under `order`.
pub fn uint16_to_bytes(w : Int, order : ByteOrder) -> (Int, Int) {
  let hi = (w >> 8) & 0xFF
  let lo = w & 0xFF
  match order {
    BigEndian => (hi, lo)
    LittleEndian => (lo, hi)
  }
}

///|
/// Rebuild a 16-bit word from two bytes (ints in 0..=255) under `order`.
/// The pair is `(first_byte, second_byte)` in wire order.
pub fn bytes_to_uint16(b0 : Int, b1 : Int, order : ByteOrder) -> Int {
  match order {
    BigEndian => (b0 << 8) | b1
    LittleEndian => (b1 << 8) | b0
  }
}

///|
/// The unsigned 16-bit word for a coil bit (0 or 1).
pub fn encode_coil(value : Bool) -> Int {
  if value {
    1
  } else {
    0
  }
}

///|
/// Decode a coil bit from a 16-bit word; any non-zero value counts as on.
pub fn decode_coil(word : Int) -> Bool {
  (word & 0xFFFF) != 0
}

///|
/// The unsigned 16-bit word for a `uint16` value (0..=65535).
pub fn encode_uint16(v : Int) -> Int {
  v & 0xFFFF
}

///|
/// Decode a `uint16` value from a word (0..=65535).
pub fn decode_uint16(word : Int) -> Int {
  word & 0xFFFF
}

///|
/// Map a signed `int16` (-32768..=32767) onto its unsigned 16-bit word.
pub fn encode_int16(v : Int) -> Int {
  v & 0xFFFF
}

///|
/// Map an unsigned 16-bit word back to a signed `int16` (two's complement).
pub fn decode_int16(word : Int) -> Int {
  let u = word & 0xFFFF
  if u >= 0x8000 {
    u - 0x10000
  } else {
    u
  }
}

///|
/// Split a 32-bit `int` into its high and low 16-bit words (unsigned).
pub fn int32_parts(v : Int) -> (Int, Int) {
  let hi = (v >> 16) & 0xFFFF
  let lo = v & 0xFFFF
  (hi, lo)
}

///|
/// Fold two unsigned 16-bit words back into a signed 32-bit `int`.
/// Because `Int` is 32-bit two's complement, `(hi << 16) | lo` already yields
/// the correct signed value for both positive and negative inputs.
pub fn int32_fold(hi : Int, lo : Int) -> Int {
  (hi << 16) | (lo & 0xFFFF)
}

///|
/// The two words of a 32-bit `int` in the register order they occupy on the
/// wire: the first element goes to the lower register address.
pub fn int32_words(v : Int, order : WordOrder) -> (Int, Int) {
  let (hi, lo) = int32_parts(v)
  match order {
    HighWordLowAddress => (hi, lo)
    LowWordLowAddress => (lo, hi)
  }
}

///|
/// Rebuild a 32-bit `int` from the two words as transmitted, given their order.
/// The pair is `(lower_address_word, higher_address_word)`.
pub fn int32_fold_words(w0 : Int, w1 : Int, order : WordOrder) -> Int {
  let atLowAddr = w0 & 0xFFFF
  let atHighAddr = w1 & 0xFFFF
  match order {
    // With native order the high word sits at the lower address, so `w0` is hi.
    HighWordLowAddress => int32_fold(atLowAddr, atHighAddr)
    // With swapped order the low word sits at the lower address, so `w1` is hi.
    LowWordLowAddress => int32_fold(atHighAddr, atLowAddr)
  }
}

///|
/// Encode a 32-bit value into a Modbus byte payload ([hi..lo] per word) given
/// both byte and word order. Returns 4 bytes in wire order, ints in 0..=255.
pub fn encode_int32_bytes(
  v : Int,
  byteOrder : ByteOrder,
  wordOrder : WordOrder,
) -> Array[Int] {
  let (wLow, wHigh) = int32_words(v, wordOrder)
  let (b0, b1) = uint16_to_bytes(wLow, byteOrder)
  let (b2, b3) = uint16_to_bytes(wHigh, byteOrder)
  [b0, b1, b2, b3]
}

///|
/// Decode a 4-byte Modbus payload back into a 32-bit `int`.
pub fn decode_int32_bytes(
  bytes : Array[Int],
  byteOrder : ByteOrder,
  wordOrder : WordOrder,
) -> Int {
  let b0 = bytes[0] & 0xFF
  let b1 = bytes[1] & 0xFF
  let b2 = bytes[2] & 0xFF
  let b3 = bytes[3] & 0xFF
  let wLow = bytes_to_uint16(b0, b1, byteOrder)
  let wHigh = bytes_to_uint16(b2, b3, byteOrder)
  int32_fold_words(wLow, wHigh, wordOrder)
}

///|
test "uint16 bytes differ under big vs little endian" {
  let be = uint16_to_bytes(0x1234, BigEndian)
  let le = uint16_to_bytes(0x1234, LittleEndian)
  assert_eq(be, (0x12, 0x34))
  assert_eq(le, (0x34, 0x12))
}

///|
test "bytes and words round trip" {
  assert_eq(bytes_to_uint16(0x12, 0x34, BigEndian), 0x1234)
  assert_eq(bytes_to_uint16(0x34, 0x12, LittleEndian), 0x1234)
  // The swap of a swap is identity (compared by name, since these types have
  // no derived Eq and comparing enums directly triggers a deprecation warning).
  assert_eq(byte_order_name(swap_byte_order(BigEndian)), "little-endian")
  assert_eq(word_order_name(swap_word_order(LowWordLowAddress)), "hi-lo")
}

///|
test "int16 two's complement maps negative values" {
  assert_eq(encode_int16(0), 0)
  assert_eq(encode_int16(-1), 0xFFFF)
  assert_eq(encode_int16(32767), 0x7FFF)
  assert_eq(decode_int16(0xFFFF), -1)
  assert_eq(decode_int16(0x8000), -32768)
  assert_eq(decode_int16(0x7FFF), 32767)
  assert_eq(decode_int16(encode_int16(-249)), -249)
}

///|
test "coil maps to 0 or 1 and decodes any non-zero as on" {
  assert_eq(encode_coil(true), 1)
  assert_eq(encode_coil(false), 0)
  assert_eq(decode_coil(1), true)
  assert_eq(decode_coil(0), false)
  assert_eq(decode_coil(0x8000), true)
}

///|
test "int32_parts separates high and low words" {
  assert_eq(int32_parts(0x12345678), (0x1234, 0x5678))
  assert_eq(int32_fold(0x1234, 0x5678), 0x12345678)
  // Negative values keep the two's-complement high word.
  let (hi, lo) = int32_parts(-1)
  assert_eq(hi, 0xFFFF)
  assert_eq(lo, 0xFFFF)
  assert_eq(int32_fold(0xFFFF, 0xFFFF), -1)
}

///|
test "int32_words respects word order" {
  assert_eq(int32_words(0x12345678, HighWordLowAddress), (0x1234, 0x5678))
  assert_eq(int32_words(0x12345678, LowWordLowAddress), (0x5678, 0x1234))
  assert_eq(int32_fold_words(0x1234, 0x5678, HighWordLowAddress), 0x12345678)
  assert_eq(int32_fold_words(0x5678, 0x1234, LowWordLowAddress), 0x12345678)
}

///|
test "int32 byte encoding round trips under every endianness" {
  let values = [0, 1, -1, 32767, -32768, 0x12345678]
  for v in values {
    let be = encode_int32_bytes(v, BigEndian, HighWordLowAddress)
    assert_eq(decode_int32_bytes(be, BigEndian, HighWordLowAddress), v)
    let le = encode_int32_bytes(v, LittleEndian, LowWordLowAddress)
    assert_eq(decode_int32_bytes(le, LittleEndian, LowWordLowAddress), v)
  }
}

///|
test "swapping byte or word order changes the encoded payload" {
  let a = encode_int32_bytes(0x12345678, BigEndian, HighWordLowAddress)
  let b = encode_int32_bytes(0x12345678, LittleEndian, HighWordLowAddress)
  let c = encode_int32_bytes(0x12345678, BigEndian, LowWordLowAddress)
  assert_eq(a[0], 0x12)
  assert_eq(c[0], 0x56) // low word moved to the lower address
  let mut differ = 0
  for k = 0; k < a.length(); k = k + 1 {
    if a[k] != b[k] {
      differ = differ + 1
    }
  }
  assert_eq(differ > 0, true)
}
