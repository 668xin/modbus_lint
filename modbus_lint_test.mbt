// 黑盒测试：只通过 modbus_lint 的对外 API（parse_device / lint / render / error_count）
// 使用点表文本作为输入，覆盖"真实用法"路径，而不是内部结构。
// 运行：moon test

test "blackbox: 合法点表不产生任何问题" {
  let text =
    "coil_temp 40001 float32 R degC jsonb->coil_temp\n"
    + "conveyor  40003 bool    RW      jsonb->conveyor_run\n"
  let dev = @modbus_lint.parse_device(text).unwrap()
  let issues = @modbus_lint.lint(dev)
  assert_eq(issues.length(), 0)
  assert_eq(@modbus_lint.render(issues), "OK: no issues found.")
}

test "blackbox: 检出同区地址重叠" {
  let text = "big   40010 float32 R\n" + "small 40011 int16   R\n"
  let dev = @modbus_lint.parse_device(text).unwrap()
  let issues = @modbus_lint.lint(dev)
  assert_eq(issues.length() > 0, true)
  assert_eq(@modbus_lint.error_count(issues) > 0, true)
}

test "blackbox: 检出寄存器重名" {
  let text = "a 40001 int16 R\n" + "a 40003 int16 R\n"
  let dev = @modbus_lint.parse_device(text).unwrap()
  assert_eq(@modbus_lint.lint(dev).length() > 0, true)
}

test "blackbox: 检出越界地址" {
  let text = "a 50001 int16 R\n"
  let dev = @modbus_lint.parse_device(text).unwrap()
  assert_eq(@modbus_lint.error_count(@modbus_lint.lint(dev)) > 0, true)
}

test "blackbox: 不同类型区域互不干扰" {
  // 30001(输入寄存器) 与 40001(保持寄存器) 属于不同区域，不应判为重叠
  let text = "ir 30001 float32 R\n" + "hr 40001 float32 R\n"
  let dev = @modbus_lint.parse_device(text).unwrap()
  assert_eq(@modbus_lint.lint(dev).length(), 0)
}

test "blackbox: 解析失败返回 Err" {
  assert_eq(@modbus_lint.parse_device("x 40001 notatype R").is_ok(), false)
}
