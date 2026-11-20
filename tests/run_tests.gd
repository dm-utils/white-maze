extends WhiteTestRunner
## Test runner: godot --headless --path . res://tests/run_tests.tscn [-- --min-checks=N]

const SUITES := [
]


func _run() -> void:
	for path in SUITES:
		await load(path).new().run(check, self)
