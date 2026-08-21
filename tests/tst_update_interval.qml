import QtQuick
import QtTest
import "../lib/UpdateInterval.js" as UpdateInterval

TestCase {
  name: "UpdateInterval"

  function test_parse_data() {
    return [
      { tag: "minimum", input: "100", expected: 100 },
      { tag: "maximum", input: "86400000", expected: 86400000 },
      { tag: "custom", input: "312", expected: 312 },
      { tag: "trimmed", input: " 400 ", expected: 400 },
      { tag: "below minimum", input: "99", expected: null },
      { tag: "above maximum", input: "86400001", expected: null },
      { tag: "empty", input: "", expected: null },
      { tag: "decimal", input: "312.5", expected: null },
      { tag: "text", input: "fast", expected: null }
    ]
  }

  function test_parse(data) {
    compare(UpdateInterval.parse(data.input), data.expected)
  }

  function test_nudge_data() {
    return [
      { tag: "left", input: 173, direction: -1, expected: 172 },
      { tag: "right", input: 173, direction: 1, expected: 174 },
      { tag: "minimum stops", input: 100, direction: -1, expected: 100 },
      {
        tag: "maximum stops",
        input: 86400000,
        direction: 1,
        expected: 86400000
      }
    ]
  }

  function test_nudge(data) {
    compare(UpdateInterval.nudge(data.input, data.direction), data.expected)
  }

  function test_nudge_repeats() {
    var value = 173
    for (var repeat = 0; repeat < 100; repeat++)
      value = UpdateInterval.nudge(value, 1)
    compare(value, 273)
  }

  function test_ladder_data() {
    return [
      { tag: "312 up", input: 312, direction: 1, expected: 500 },
      { tag: "312 down", input: 312, direction: -1, expected: 250 },
      { tag: "250 up", input: 250, direction: 1, expected: 500 },
      { tag: "250 down wraps", input: 250, direction: -1, expected: 5000 },
      { tag: "5000 up wraps", input: 5000, direction: 1, expected: 250 },
      { tag: "5000 down", input: 5000, direction: -1, expected: 2000 },
      { tag: "below ladder up", input: 100, direction: 1, expected: 250 },
      {
        tag: "below ladder down",
        input: 249,
        direction: -1,
        expected: 5000
      },
      {
        tag: "above ladder up",
        input: 5001,
        direction: 1,
        expected: 250
      },
      {
        tag: "above ladder down",
        input: 86400000,
        direction: -1,
        expected: 5000
      }
    ]
  }

  function test_ladder(data) {
    compare(UpdateInterval.ladder(data.input, data.direction), data.expected)
  }
}
