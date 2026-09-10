// Statistics: turn a `Device` into aggregate, quantified facts about how the
// Modbus address space is used. Where `tools.mbt` gives narrow per-area/type
// counts, this module builds a single `DeviceStats` snapshot you can render or
// reason about, plus a few density helpers that drive allocation advice.

///|
/// Per-area summarised allocation.
pub struct AreaStats {
  area : Int
  /// Number of registers mapped into this area.
  registers : Int
  /// Total words occupied by those registers (accounting for each type width).
  words : Int
  /// Words that remain unused out of the area's 9999-word capacity.
  free_words : Int
  /// Utilisation as parts per thousand (0..1000).
  utilization_permille : Int
  /// Total bytes consumed (words * 2).
  bytes : Int
}

///|
/// Whole-device stats snapshot.
pub struct DeviceStats {
  total_registers : Int
  /// Sum of `word_count` over all registers.
  total_words : Int
  /// `total_words` in bytes (Modbus word = 2 bytes).
  total_bytes : Int
  /// Number of coil/discrete-input (bit) registers.
  bit_registers : Int
  /// Number of registers that carry a usable jsonb mapping.
  jsonb_mapped : Int
  /// Number of registers without an explicit unit string.
  unitless : Int
  /// Shortest register-name length observed (0 for an empty device).
  min_name_len : Int
  /// Longest register-name length observed (0 for an empty device).
  max_name_len : Int
  /// Average name length, rounded down.
  avg_name_len : Int
  /// Per-area rows, in the standard 0..4 order (area 2 omitted).
  areas : Array[AreaStats]
}

///|
/// Accumulate utilisation info for one area; capacity is 9999 words.
fn area_usage(dev : Device, area : Int) -> AreaStats {
  let mut registers = 0
  let mut words = 0
  for r in dev.registers {
    if area_of(r.address) == area {
      registers = registers + 1
      words = words + word_count(r.rtype)
    }
  }
  let free = 9999 - words
  let permille = if words > 0 { words * 1000 / 9999 } else { 0 }
  {
    area,
    registers,
    words,
    free_words: free,
    utilization_permille: permille,
    bytes: words * 2,
  }
}

///|
/// Build a full statistics snapshot for a `Device`.
pub fn compute_stats(dev : Device) -> DeviceStats {
  let _all : Array[Register] = dev.registers
  let mut total_words = 0
  let mut bit_registers = 0
  let mut jsonb_mapped = 0
  let mut unitless = 0
  let mut min_len = 0
  let mut max_len = 0
  let mut sum_len = 0
  let mut first = true
  for r in dev.registers {
    total_words = total_words + word_count(r.rtype)
    if area_is_bit(area_of(r.address)) {
      bit_registers = bit_registers + 1
    }
    if !jsonb_is_unset(r.jsonb) {
      jsonb_mapped = jsonb_mapped + 1
    }
    if r.unit.length() == 0 {
      unitless = unitless + 1
    }
    let l = r.name.length()
    if first {
      min_len = l
      max_len = l
      first = false
    } else {
      if l < min_len {
        min_len = l
      }
      if l > max_len {
        max_len = l
      }
    }
    sum_len = sum_len + l
  }
  let total = dev.registers.length()
  let avg = if total > 0 { sum_len / total } else { 0 }
  let areas : Array[AreaStats] = []
  // Treat only the four real areas; area 2 is reserved/nonexistent.
  for i = 0; i < 5; i = i + 1 {
    if i == 2 {
      continue
    }
    areas.push(area_usage(dev, i))
  }
  {
    total_registers: total,
    total_words,
    total_bytes: total_words * 2,
    bit_registers,
    jsonb_mapped,
    unitless,
    min_name_len: min_len,
    max_name_len: max_len,
    avg_name_len: avg,
    areas,
  }
}

///|
/// Total free words across every real area.
pub fn total_free_words(stats : DeviceStats) -> Int {
  let mut sum = 0
  for a in stats.areas {
    sum = sum + a.free_words
  }
  sum
}

///|
/// The area with the largest absolute word consumption.
/// Returns `(-1, 0)` when the device is empty.
pub fn dominant_area(dev : Device) -> (Int, Int) {
  let mut best_area = -1
  let mut best_words = 0
  let areas = compute_stats(dev).areas
  for a in areas {
    if a.words > best_words {
      best_words = a.words
      best_area = a.area
    }
  }
  (best_area, best_words)
}

///|
/// Smallest and largest address gaps (in words) between consecutive registers
/// in the same area, computed from the whole device. `(0, 0)` when there are
/// fewer than two registers in any single area.
pub fn gap_bounds(dev : Device) -> (Int, Int) {
  let areas = count_by_area(dev)
  let mut min_gap = -1
  let mut max_gap = 0
  for (area, _count) in areas {
    let sorted = sort_by_address(filter_area(dev, area)).registers
    if sorted.length() < 2 {
      continue
    }
    let base = area_base(area)
    for i = 1; i < sorted.length(); i = i + 1 {
      let prev_hi = sorted[i - 1].address -
        base +
        word_count(sorted[i - 1].rtype)
      let cur_lo = sorted[i].address - base + 0
      let gap = cur_lo - prev_hi
      if gap < 0 {
        continue // registers overlap; not treated as a gap
      }
      if min_gap < 0 || gap < min_gap {
        min_gap = gap
      }
      if gap > max_gap {
        max_gap = gap
      }
    }
  }
  if min_gap < 0 {
    min_gap = 0
  }
  (min_gap, max_gap)
}

///|
/// Render the stats snapshot as a compact text block (used by the CLI summary).
pub fn stats_text(dev : Device) -> String {
  let s = compute_stats(dev)
  let out = StringBuilder()
  out.write_string("total registers: " + s.total_registers.to_string() + "\n")
  out.write_string("total words: " + s.total_words.to_string() + "\n")
  out.write_string("total bytes: " + s.total_bytes.to_string() + "\n")
  out.write_string("bit registers: " + s.bit_registers.to_string() + "\n")
  out.write_string("jsonb mapped: " + s.jsonb_mapped.to_string() + "\n")
  out.write_string("unitless: " + s.unitless.to_string() + "\n")
  out.write_string(
    "name length (min/max/avg): " +
    s.min_name_len.to_string() +
    "/" +
    s.max_name_len.to_string() +
    "/" +
    s.avg_name_len.to_string() +
    "\n",
  )
  for a in s.areas {
    out.write_string(
      area_name(a.area) +
      ": " +
      a.registers.to_string() +
      " reg, " +
      a.words.to_string() +
      "/" +
      a.free_words.to_string() +
      " words free (" +
      (a.utilization_permille / 10).to_string() +
      "%)\n",
    )
  }
  out.to_string()
}

///|
test "compute_stats tallies the whole device" {
  let dev : Device = {
    registers: [
      {
        name: "a",
        address: 40001,
        rtype: TFloat32,
        access: Read,
        unit: "degC",
        jsonb: "jsonb->a",
        line: 1,
      },
      {
        name: "bb",
        address: 1001,
        rtype: TBit,
        access: Read,
        unit: "",
        jsonb: "",
        line: 2,
      },
    ],
  }
  let s = compute_stats(dev)
  assert_eq(s.total_registers, 2)
  assert_eq(s.total_words, 3) // float32 = 2 words + coil = 1 word
  assert_eq(s.total_bytes, 6)
  assert_eq(s.bit_registers, 1)
  assert_eq(s.jsonb_mapped, 1)
  assert_eq(s.unitless, 1)
}

///|
test "area usage matches per-area free words" {
  let dev : Device = {
    registers: [
      {
        name: "a",
        address: 40001,
        rtype: TInt16,
        access: Read,
        unit: "",
        jsonb: "",
        line: 1,
      },
      {
        name: "b",
        address: 40002,
        rtype: TFloat32,
        access: Read,
        unit: "",
        jsonb: "",
        line: 2,
      },
    ],
  }
  let s = compute_stats(dev)
  // Holding area: 1 + 2 = 3 words used, 9996 free.
  let mut hr : AreaStats = {
    area: 0,
    registers: 0,
    words: 0,
    free_words: 0,
    utilization_permille: 0,
    bytes: 0,
  }
  for a in s.areas {
    if a.area == 4 {
      hr = a
    }
  }
  assert_eq(hr.words, 3)
  assert_eq(hr.free_words, 9996)
  assert_eq(hr.bytes, 6)
}

///|
test "gap_bounds returns min and max intra-area gaps" {
  let dev : Device = {
    registers: [
      {
        name: "a",
        address: 40001,
        rtype: TInt16,
        access: Read,
        unit: "",
        jsonb: "",
        line: 1,
      },
      {
        name: "b",
        address: 40004,
        rtype: TInt16,
        access: Read,
        unit: "",
        jsonb: "",
        line: 2,
      },
    ],
  }
  // a occupies word 0; b starts at word 3 => gap of 2 words.
  assert_eq(gap_bounds(dev), (2, 2))
}

///|
test "dominant_area picks the area with the most words" {
  let dev : Device = {
    registers: [
      {
        name: "a",
        address: 40001,
        rtype: TFloat64,
        access: Read,
        unit: "",
        jsonb: "",
        line: 1,
      },
      {
        name: "b",
        address: 1001,
        rtype: TBit,
        access: Read,
        unit: "",
        jsonb: "",
        line: 2,
      },
    ],
  }
  assert_eq(dominant_area(dev), (4, 4)) // float64 = 4 words in holding area
}

///|
test "stats_text includes the summary lines" {
  let dev : Device = { registers: [], }
  let t = stats_text(dev)
  assert_eq(t.contains("total registers: 0"), true)
  assert_eq(t.contains("total words: 0"), true)
  assert_eq(t.contains("coils: 0 reg"), true)
}

///|
test "name length bounds are tracked across registers" {
  let dev : Device = {
    registers: [
      {
        name: "x",
        address: 40001,
        rtype: TInt16,
        access: Read,
        unit: "",
        jsonb: "",
        line: 1,
      },
      {
        name: "longer_name",
        address: 40002,
        rtype: TInt16,
        access: Read,
        unit: "",
        jsonb: "",
        line: 2,
      },
    ],
  }
  let s = compute_stats(dev)
  assert_eq(s.min_name_len, 1)
  assert_eq(s.max_name_len, 11)
  assert_eq(s.avg_name_len, 6)
}
