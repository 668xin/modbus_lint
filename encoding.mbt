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

// ---------------------------------------------------------------------------
// Floating point.
//
// MoonBit does not expose a Double <-> Int64 bit-cast primitive, so these
// functions build and tear down the IEEE-754 pattern with plain arithmetic:
//   - encode: normalise the magnitude into [1, 2), then scale the mantissa
//     into a 52/23-bit integer (via the exact `Double.to_int64()` truncation).
//   - decode: rebuild the value as `(2^52 | mant) * 2^(E - 1075)`, which is an
//     exact integer-times-power-of-two that reproduces the original double.
//
// The APIs use a fixed big-endian word order (most-significant word first).
// Per-word byte order is supported through the *bytes helpers, reusing
// `uint16_to_bytes` / `bytes_to_uint16`.
// ---------------------------------------------------------------------------

///|
/// The 16-bit WORD PACK that a double occupies, high word first.
fn split_words64(b : Int64) -> (Int, Int, Int, Int) {
  let w0 = ((b >> 48) & 0xFFFFL).to_int()
  let w1 = ((b >> 32) & 0xFFFFL).to_int()
  let w2 = ((b >> 16) & 0xFFFFL).to_int()
  let w3 = (b & 0xFFFFL).to_int()
  (w0, w1, w2, w3)
}

///|
/// The reverse of `split_words64`.
fn compose_words64(w0 : Int, w1 : Int, w2 : Int, w3 : Int) -> Int64 {
  (w0.to_int64() << 48) |
  (w1.to_int64() << 32) |
  (w2.to_int64() << 16) |
  w3.to_int64()
}

///|
/// IEEE-754 double-precision bits for a finite (or special) `Double`.
fn double_bits(v : Double) -> Int64 {
  if v != v {
    // NaN: canonical quiet NaN (exponent all ones, top mantissa bit set).
    return 0x7FF8000000000000L
  }
  let neg = if v < 0.0 {
    true
  } else if v == 0.0 {
    1.0 / v < 0.0
  } else {
    false
  }
  let g = v.abs()
  if g == 0.0 {
    return if neg { 0x8000000000000000L } else { 0L }
  }
  if g > 1.7976931348623157e308 {
    // Infinity: exponent all ones, mantissa zero.
    let inf = 0x7FF0000000000000L
    return if neg { inf | 0x8000000000000000L } else { inf }
  }
  // Normalise magnitude into [1, 2).
  let mut m = g
  let mut e2 = 0
  if m >= 2.0 {
    while m >= 2.0 {
      m = m * 0.5
      e2 = e2 + 1
    }
  } else if m < 1.0 {
    while m < 1.0 {
      m = m * 2.0
      e2 = e2 - 1
    }
  }
  let exp_field_raw = e2 + 1023
  if exp_field_raw <= 0 {
    // Subnormal: reproduce the value as raw scaled integer mantissa words.
    let scaled = (g * @math.pow(2.0, 1074.0) + 0.5).to_int64()
    let mant = scaled & 0xFFFFFFFFFFFFFL
    let sign = if neg { 0x8000000000000000L } else { 0L }
    return sign | mant
  }
  let frac = m - 1.0
  let mut mant = (frac * 4503599627370496.0 + 0.5).to_int64()
  let mut ef = exp_field_raw
  if mant >= 4503599627370496L {
    mant = 0L
    ef = ef + 1
  }
  let exp = ef.to_int64() << 52
  let sign = if neg { 0x8000000000000000L } else { 0L }
  sign | exp | (mant & 0xFFFFFFFFFFFFFL)
}

///|
/// Rebuild a `Double` from its IEEE-754 bit pattern.
fn double_from_bits(b : Int64) -> Double {
  let sign = (b >> 63) & 1L
  let exp = (b >> 52) & 0x7FFL
  let mant = b & 0xFFFFFFFFFFFFFL
  let mag = if exp == 0L {
    if mant == 0L {
      0.0
    } else {
      // Subnormal: value = mant * 2^-1074.
      mant.to_double() * @math.pow(2.0, -1074.0)
    }
  } else {
    // value = (2^52 set + mant) * 2^(E - 1075).
    let num = (4503599627370496L | mant).to_double()
    let pow = exp.to_int() - 1075
    num * @math.pow(2.0, pow.to_double())
  }
  if sign == 1L {
    -mag
  } else {
    mag
  }
}

///|
/// The four 16-bit words (high word first) of a double-precision value.
pub fn float64_words(v : Double) -> (Int, Int, Int, Int) {
  split_words64(double_bits(v))
}

///|
/// Rebuild a double-precision value from its four words (high word first).
pub fn float64_from_words(w0 : Int, w1 : Int, w2 : Int, w3 : Int) -> Double {
  double_from_bits(compose_words64(w0, w1, w2, w3))
}

///|
/// The eight bytes (in wire order for `byteOrder`) of a double value, walking
/// four words from the most-significant word first.
pub fn float64_bytes(v : Double, byteOrder : ByteOrder) -> Array[Int] {
  let (w0, w1, w2, w3) = float64_words(v)
  let (h0, l0) = uint16_to_bytes(w0, byteOrder)
  let (h1, l1) = uint16_to_bytes(w1, byteOrder)
  let (h2, l2) = uint16_to_bytes(w2, byteOrder)
  let (h3, l3) = uint16_to_bytes(w3, byteOrder)
  [h0, l0, h1, l1, h2, l2, h3, l3]
}

///|
/// Rebuild a double value from eight bytes produced by `float64_bytes`.
pub fn float64_from_bytes(bytes : Array[Int], byteOrder : ByteOrder) -> Double {
  let w0 = bytes_to_uint16(bytes[0] & 0xFF, bytes[1] & 0xFF, byteOrder)
  let w1 = bytes_to_uint16(bytes[2] & 0xFF, bytes[3] & 0xFF, byteOrder)
  let w2 = bytes_to_uint16(bytes[4] & 0xFF, bytes[5] & 0xFF, byteOrder)
  let w3 = bytes_to_uint16(bytes[6] & 0xFF, bytes[7] & 0xFF, byteOrder)
  float64_from_words(w0, w1, w2, w3)
}

///|
/// IEEE-754 single-precision bits for `v` (a `Double`, rounded to float32).
fn float32_bits(v : Double) -> Int {
  if v != v {
    return 0x7FC00000
  }
  let neg = if v < 0.0 {
    true
  } else if v == 0.0 {
    1.0 / v < 0.0
  } else {
    false
  }
  let g = v.abs()
  if g == 0.0 {
    return if neg { 0x80000000 } else { 0 }
  }
  let mut m = g
  let mut e2 = 0
  if m >= 2.0 {
    while m >= 2.0 {
      m = m * 0.5
      e2 = e2 + 1
    }
  } else if m < 1.0 {
    while m < 1.0 {
      m = m * 2.0
      e2 = e2 - 1
    }
  }
  let exp_raw = e2 + 127
  if exp_raw <= 0 {
    let scaled = (g * @math.pow(2.0, 149.0) + 0.5).to_int64().to_int()
    let mant = scaled & 0x7FFFFF
    let sign = if neg { 0x80000000 } else { 0 }
    return sign | mant
  }
  let frac = m - 1.0
  let mut mant = (frac * 8388608.0 + 0.5).to_int64().to_int()
  let mut ef = exp_raw
  if mant >= 8388608 {
    mant = 0
    ef = ef + 1
  }
  let sign = if neg { 0x80000000 } else { 0 }
  sign | ((ef << 23) & 0x7F800000) | (mant & 0x7FFFFF)
}

///|
/// Rebuild a single-precision value (as a `Double`) from its 32-bit bits.
fn float32_from_bits(bits : Int) -> Double {
  let sign = (bits >> 31) & 1
  let exp = (bits >> 23) & 0xFF
  let mant = bits & 0x7FFFFF
  let mag = if exp == 0 {
    if mant == 0 {
      0.0
    } else {
      mant.to_double() * @math.pow(2.0, -149.0)
    }
  } else {
    let num = (8388608 | mant).to_double()
    num * @math.pow(2.0, (exp - 150).to_double())
  }
  if sign == 1 {
    -mag
  } else {
    mag
  }
}

///|
/// The two 16-bit words (high word first) of a single-precision value.
pub fn float32_words(v : Double) -> (Int, Int) {
  let b = float32_bits(v)
  let hi = (b >> 16) & 0xFFFF
  let lo = b & 0xFFFF
  (hi, lo)
}

///|
/// Rebuild a single-precision value from its two words (high word first).
pub fn float32_from_words(hi : Int, lo : Int) -> Double {
  float32_from_bits(((hi & 0xFFFF) << 16) | (lo & 0xFFFF))
}

///|
/// The four bytes (in wire order for `byteOrder`) of a single-precision value.
pub fn float32_bytes(v : Double, byteOrder : ByteOrder) -> Array[Int] {
  let (hi, lo) = float32_words(v)
  let (b0, b1) = uint16_to_bytes(hi, byteOrder)
  let (b2, b3) = uint16_to_bytes(lo, byteOrder)
  [b0, b1, b2, b3]
}

///|
/// Rebuild a single-precision value from four bytes.
pub fn float32_from_bytes(bytes : Array[Int], byteOrder : ByteOrder) -> Double {
  let hi = bytes_to_uint16(bytes[0] & 0xFF, bytes[1] & 0xFF, byteOrder)
  let lo = bytes_to_uint16(bytes[2] & 0xFF, bytes[3] & 0xFF, byteOrder)
  float32_from_words(hi, lo)
}

///|
test "float64 round trips 1.0 through words" {
  let (w0, w1, w2, w3) = float64_words(1.0)
  // 1.0 = 0x3FF00000_00000000, so w0=0x3FF0, w1=0, then zeros.
  assert_eq(w0, 0x3FF0)
  assert_eq(w1, 0)
  assert_eq(float64_from_words(w0, w1, w2, w3), 1.0)
}

///|
test "float64 round trips a spread of values" {
  let values = [1.0, -1.0, 0.0, -0.0, 3.0, 1234.5, 0.5, -2.25]
  for v in values {
    let (w0, w1, w2, w3) = float64_words(v)
    assert_eq(float64_from_words(w0, w1, w2, w3), v)
    let bs = float64_bytes(v, BigEndian)
    assert_eq(float64_from_bytes(bs, BigEndian), v)
    let ls = float64_bytes(v, LittleEndian)
    assert_eq(float64_from_bytes(ls, LittleEndian), v)
  }
}

///|
test "float64 bytes differ under big and little endian" {
  let be = float64_bytes(1.0, BigEndian)
  let le = float64_bytes(1.0, LittleEndian)
  assert_eq(be[0], 0x3F)
  assert_eq(be[1], 0xF0)
  // Little endian flips each word's byte order (low byte first).
  assert_eq(le[0], 0xF0)
  assert_eq(le[1], 0x3F)
}

///|
test "float32 round trips values that are exactly representable" {
  let values = [1.5, -0.25, 3.0, 0.0, -0.0, 1234.0, 0.5]
  for v in values {
    let (hi, lo) = float32_words(v)
    assert_eq(float32_from_words(hi, lo), v)
    let be = float32_bytes(v, BigEndian)
    assert_eq(float32_from_bytes(be, BigEndian), v)
  }
}

///|
test "float32 encodes 1.5 to the expected words" {
  // 1.5 = sign 0, exp 127, mantissa 0x400000 => words hi=0x3FC0, lo=0x0000.
  let (hi, lo) = float32_words(1.5)
  assert_eq(hi, 0x3FC0)
  assert_eq(lo, 0)
}
