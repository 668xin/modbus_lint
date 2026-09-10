// Point-table tools and statistics: sorting, de-duplication, filtering, lookups
// and cheap aggregate metrics. Everything is a pure function over `Device`, so
// it is unit-testable without IO.

///|
/// Returns a new `Device` whose registers are sorted by address (stable
/// insertion sort, so equal addresses keep their original relative order).
pub fn sort_by_address(dev : Device) -> Device {
  let arr : Array[Register] = []
  for r in dev.registers {
    arr.push(r)
  }
  for i = 1; i < arr.length(); i = i + 1 {
    let key = arr[i]
    let mut j = i
    while j > 0 && arr[j - 1].address > key.address {
      arr[j] = arr[j - 1]
      j = j - 1
    }
    arr[j] = key
  }
  { registers: arr, }
}

///|
/// Returns a new `Device` with exact duplicate registers removed. Two registers
/// are duplicates when every field matches.
pub fn dedupe(dev : Device) -> Device {
  let out : Array[Register] = []
  for r in dev.registers {
    let mut dup = false
    for o in out {
      if o.name == r.name &&
        o.address == r.address &&
        type_name(o.rtype) == type_name(r.rtype) &&
        access_name(o.access) == access_name(r.access) &&
        o.unit == r.unit &&
        o.jsonb == r.jsonb {
        dup = true
      }
    }
    if !dup {
      out.push(r)
    }
  }
  { registers: out, }
}

///|
/// Returns a new `Device` containing only registers whose area equals `area`.
pub fn filter_area(dev : Device, area : Int) -> Device {
  let out : Array[Register] = []
  for r in dev.registers {
    if area_of(r.address) == area {
      out.push(r)
    }
  }
  { registers: out, }
}

///|
/// Find a register by exact name. Returns `None` when it is absent.
pub fn lookup(dev : Device, name : String) -> Register? {
  for r in dev.registers {
    if r.name == name {
      return Some(r)
    }
  }
  None
}

///|
/// Count how many pairs of registers share the exact same absolute address.
/// (Overlap linting is stricter; this is a cheap exact-collision metric.)
pub fn exact_address_collisions(dev : Device) -> Int {
  let regs = dev.registers
  let mut n = 0
  for i = 0; i < regs.length(); i = i + 1 {
    for j = i + 1; j < regs.length(); j = j + 1 {
      if regs[i].address == regs[j].address {
        n = n + 1
      }
    }
  }
  n
}

///|
/// How many 16-bit words each area holds in total (occupied allocation).
pub fn per_area_words(dev : Device) -> Array[(Int, Int)] {
  let out : Array[(Int, Int)] = []
  let seen : Array[Int] = []
  for r in dev.registers {
    let ar = area_of(r.address)
    if ar >= 0 && !seen.contains(ar) {
      seen.push(ar)
      let mut c = 0
      for q in dev.registers {
        if area_of(q.address) == ar {
          c = c + word_count(q.rtype)
        }
      }
      out.push((ar, c))
    }
  }
  out
}

///|
/// Registers grouped by type keyword, with the count of each type.
pub fn count_by_type(dev : Device) -> Array[(String, Int)] {
  let out : Array[(String, Int)] = []
  let seen : Array[String] = []
  for r in dev.registers {
    let tn = type_name(r.rtype)
    if !seen.contains(tn) {
      seen.push(tn)
      let mut c = 0
      for q in dev.registers {
        if type_name(q.rtype) == tn {
          c = c + 1
        }
      }
      out.push((tn, c))
    }
  }
  out
}

///|
/// Registers grouped by area id, with the count of each area.
pub fn count_by_area(dev : Device) -> Array[(Int, Int)] {
  let out : Array[(Int, Int)] = []
  let seen : Array[Int] = []
  for r in dev.registers {
    let ar = area_of(r.address)
    if ar >= 0 && !seen.contains(ar) {
      seen.push(ar)
      let mut c = 0
      for q in dev.registers {
        if area_of(q.address) == ar {
          c = c + 1
        }
      }
      out.push((ar, c))
    }
  }
  out
}

///|
/// Access modes used, with the count of each mode.
pub fn count_by_access(dev : Device) -> Array[(String, Int)] {
  let out : Array[(String, Int)] = []
  let seen : Array[String] = []
  for r in dev.registers {
    let an = access_name(r.access)
    if !seen.contains(an) {
      seen.push(an)
      let mut c = 0
      for q in dev.registers {
        if access_name(q.access) == an {
          c = c + 1
        }
      }
      out.push((an, c))
    }
  }
  out
}

///|
/// A one-shot human summary of the point-table shape (counts per area/type/access).
pub fn stats_summary(dev : Device) -> String {
  let out = StringBuilder()
  out.write_string("registers: " + dev.registers.length().to_string() + "\n")
  for (area, c) in count_by_area(dev) {
    out.write_string(area_name(area) + ": " + c.to_string() + "\n")
  }
  out.to_string()
}

///|
test "sort_by_address orders registers by address" {
  let dev : Device = {
    registers: [
      {
        name: "b",
        address: 40003,
        rtype: TInt16,
        access: Read,
        unit: "",
        jsonb: "",
        line: 2,
      },
      {
        name: "a",
        address: 40001,
        rtype: TInt16,
        access: Read,
        unit: "",
        jsonb: "",
        line: 1,
      },
    ],
  }
  let s = sort_by_address(dev)
  assert_eq(s.registers[0].address, 40001)
  assert_eq(s.registers[1].address, 40003)
}

///|
test "dedupe removes exact duplicates" {
  let dev : Device = {
    registers: [
      {
        name: "a",
        address: 40001,
        rtype: TInt16,
        access: Read,
        unit: "",
        jsonb: "jsonb->a",
        line: 1,
      },
      {
        name: "a",
        address: 40001,
        rtype: TInt16,
        access: Read,
        unit: "",
        jsonb: "jsonb->a",
        line: 2,
      },
      {
        name: "b",
        address: 40003,
        rtype: TInt16,
        access: Read,
        unit: "",
        jsonb: "",
        line: 3,
      },
    ],
  }
  assert_eq(dedupe(dev).registers.length(), 2)
}

///|
test "filter_area keeps only the requested area" {
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
        address: 1001,
        rtype: TBit,
        access: Read,
        unit: "",
        jsonb: "",
        line: 2,
      },
    ],
  }
  let hr = filter_area(dev, 4)
  assert_eq(hr.registers.length(), 1)
  assert_eq(hr.registers[0].address, 40001)
}

///|
test "lookup finds a register by name" {
  let dev : Device = {
    registers: [
      {
        name: "temp",
        address: 40001,
        rtype: TFloat32,
        access: Read,
        unit: "",
        jsonb: "",
        line: 1,
      },
    ],
  }
  assert_eq(lookup(dev, "temp") is Some(_), true)
  assert_eq(lookup(dev, "nope") is None, true)
}

///|
test "exact_address_collisions counts shared addresses" {
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
        address: 40001,
        rtype: TInt16,
        access: Read,
        unit: "",
        jsonb: "",
        line: 2,
      },
      {
        name: "c",
        address: 40003,
        rtype: TInt16,
        access: Read,
        unit: "",
        jsonb: "",
        line: 3,
      },
    ],
  }
  assert_eq(exact_address_collisions(dev), 1)
}

///|
test "count_by_type tallies registers per type" {
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
        rtype: TInt16,
        access: Read,
        unit: "",
        jsonb: "",
        line: 2,
      },
      {
        name: "c",
        address: 1001,
        rtype: TBit,
        access: Read,
        unit: "",
        jsonb: "",
        line: 3,
      },
    ],
  }
  let counts = count_by_type(dev)
  assert_eq(counts.length(), 2)
  assert_eq(counts[0].1, 2)
}

///|
test "per_area_words sums word counts per area" {
  let dev : Device = {
    registers: [
      {
        name: "a",
        address: 40001,
        rtype: TFloat32,
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
  let words = per_area_words(dev)
  // float32 is 2 words; the bit is 1 word in the coils area.
  assert_eq(words[0].1, 2)
}

///|
/// Build a 0-based map of which words inside `area` are occupied by registers.
fn occupied_word_map(dev : Device, area : Int) -> Array[Bool] {
  let used : Array[Bool] = []
  for k = 0; k < 9999; k = k + 1 {
    used.push(false)
  }
  let base = area_base(area)
  if base == 0 {
    return used
  }
  for r in dev.registers {
    if area_of(r.address) != area {
      continue
    }
    let lo = r.address - base
    let w = word_count(r.rtype)
    for k = 0; k < w; k = k + 1 {
      if lo + k < 9999 {
        used[lo + k] = true
      }
    }
  }
  used
}

///|
/// The 0-based local word bounds `(lo, hi)` that `area` occupies
/// (inclusive); `(-1, -1)` when the area has no register.
pub fn area_bounds(dev : Device, area : Int) -> (Int, Int) {
  let mut lo = -1
  let mut hi = -1
  for r in dev.registers {
    if area_of(r.address) != area {
      continue
    }
    let base = area_base(area)
    let l = r.address - base
    let h = l + word_count(r.rtype) - 1
    if lo < 0 || l < lo {
      lo = l
    }
    if h > hi {
      hi = h
    }
  }
  (lo, hi)
}

///|
/// The lowest absolute address in `area` that is not yet used by a register.
pub fn first_free_address(dev : Device, area : Int) -> Int {
  let base = area_base(area)
  if base == 0 {
    return 0
  }
  let used = occupied_word_map(dev, area)
  for i = 0; i < used.length(); i = i + 1 {
    if !used[i] {
      return base + i
    }
  }
  0
}

///|
/// How many 16-bit words in `area` are still unallocated.
pub fn free_word_count(dev : Device, area : Int) -> Int {
  let used = occupied_word_map(dev, area)
  let mut free = 0
  for u in used {
    if !u {
      free = free + 1
    }
  }
  free
}

///|
/// For each register, record the gap (in words) to the next occupied register
/// in the same area when that gap is strictly greater than `threshold`.
/// Returns `(name, address, gap_words)` triples, e.g. useful to pre-check
/// allocation density before running the linter.
pub fn gap_pairs(dev : Device, threshold : Int) -> Array[(String, Int, Int)] {
  let out : Array[(String, Int, Int)] = []
  let regs = sort_by_address(dev).registers
  for i = 0; i < regs.length(); i = i + 1 {
    let a = regs[i]
    let area = area_of(a.address)
    if area < 0 {
      continue
    }
    let base = area_base(area)
    let hi = a.address - base + word_count(a.rtype)
    let mut next_lo = -1
    for j = 0; j < regs.length(); j = j + 1 {
      let b = regs[j]
      if j != i && area_of(b.address) == area {
        let lo2 = b.address - base + 1
        if lo2 > hi && (next_lo < 0 || lo2 < next_lo) {
          next_lo = lo2
        }
      }
    }
    if next_lo > 0 {
      let gap = next_lo - hi - 1
      if gap > threshold {
        out.push((a.name, a.address, gap))
      }
    }
  }
  out
}

///|
test "area_bounds / free_word_count / first_free_address describe an area" {
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
        rtype: TInt16,
        access: Read,
        unit: "",
        jsonb: "",
        line: 2,
      },
    ],
  }
  // Words 0 and 1 are used (addresses 40001, 40002).
  assert_eq(area_bounds(dev, 4), (0, 1))
  // Two words used out of 9999, so 9997 remain free.
  assert_eq(free_word_count(dev, 4), 9997)
  // The next free holding-register address is 40003.
  assert_eq(first_free_address(dev, 4), 40003)
  // A coil area with no register reports "-1" bounds.
  assert_eq(area_bounds(dev, 0), (-1, -1))
}

///|
test "gap_pairs lists only gaps above the threshold" {
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
        address: 40011,
        rtype: TInt16,
        access: Read,
        unit: "",
        jsonb: "",
        line: 2,
      },
      {
        name: "c",
        address: 40020,
        rtype: TInt16,
        access: Read,
        unit: "",
        jsonb: "",
        line: 3,
      },
    ],
  }
  // gap a->b = 9, b->c = 8; with a tight threshold both are reported.
  let pairs = gap_pairs(dev, 4)
  assert_eq(pairs.length(), 2)
  assert_eq(pairs[0].0, "a")
  // With a high threshold nothing exceeds it.
  assert_eq(gap_pairs(dev, 100).length(), 0)
}
