extends WhiteTestRunner
## Test runner: godot --headless --path . res://tests/run_tests.tscn [-- --min-checks=N]

const SUITES := [
	"res://tests/tuning_tests.gd",
	"res://tests/aim_tests.gd",
	"res://tests/move_tests.gd",
	"res://tests/ring_tests.gd",
	"res://tests/rules_tests.gd",
	"res://tests/run_script_tests.gd",
	"res://tests/profile_tests.gd",
	"res://tests/level_tests.gd",
	"res://tests/solution_tests.gd",
	"res://tests/fuzz_tests.gd",
	"res://tests/robust_tests.gd",
	"res://tests/controls_tests.gd",
	"res://tests/profile_store_tests.gd",
	"res://tests/camera_tests.gd",
	"res://tests/ui_tests.gd",
	"res://tests/art_tests.gd",
	"res://tests/feel_tests.gd",
	"res://tests/screens_tester_tests.gd",
]


func _run() -> void:
	for path in SUITES:
		await load(path).new().run(check, self)
