class_name MazeTuning
extends RefCounted
## Simulation tuning. Every value twice: readable (_PX, _S) and the integer the sim uses; tuning_tests keeps them equal.
## Units: 1/1000 px; speeds per tick, accelerations per tick per tick, times in ticks.

const UNITS_PER_PX := 1000
const TILE := 40000
const TICK_HZ := 60

const RUN_SPEED_PX := 300.0
const GROUND_ACCEL_PX := 2400.0
const GROUND_DECEL_PX := 3000.0
const AIR_ACCEL_PX := 1600.0
const AIR_TURN_PX := 2000.0
const AIR_DRAG_PX := 300.0
const JUMP_SPEED_PX := 800.0
const GRAVITY_UP_PX := 2400.0
const GRAVITY_DOWN_PX := 3600.0
const APEX_THRESHOLD_PX := 60.0
const APEX_GRAVITY_PX := 1200.0
const MAX_FALL_PX := 900.0
const COYOTE_S := 0.10
const JUMP_BUFFER_S := 0.133
const CORNER_CORRECTION_PX := 8.0
const FLOOR_LAUNCH_PX := 1080.0
const WALL_LAUNCH_X_PX := 640.0
const WALL_LAUNCH_LIFT_PX := 560.0
const CEILING_LAUNCH_PX := 900.0
const WALL_LOCK_S := 0.2
const RING_COOLDOWN_S := 0.167
const BEAD_SPEED_PX := 1600.0
const CAST_RANGE_PX := 800.0
const CAST_STEP_PX := 2.0
const DEATH_S := 0.5
const PLAYER_W_PX := 30.0
const PLAYER_H_PX := 32.0
const HAZARD_INSET_PX := 4.0
const RING_DEPTH_PX := 8.0
const RING_INSET_PX := 4.0
const SPIKE_INSET_PX := 4.0

const RUN_SPEED := 5000
const GROUND_ACCEL := 667
const GROUND_DECEL := 833
const AIR_ACCEL := 444
const AIR_TURN := 556
const AIR_DRAG := 83
const JUMP_SPEED := 13333
const GRAVITY_UP := 667
const GRAVITY_DOWN := 1000
const APEX_THRESHOLD := 1000
const APEX_GRAVITY := 333
const MAX_FALL := 15000
const COYOTE_TICKS := 6
const JUMP_BUFFER_TICKS := 8
const CORNER_CORRECTION := 8000
const FLOOR_LAUNCH := 18000
const WALL_LAUNCH_X := 10667
const WALL_LAUNCH_LIFT := 9333
const CEILING_LAUNCH := 15000
const WALL_LOCK_TICKS := 12
const RING_COOLDOWN_TICKS := 10
const BEAD_SPEED := 26667
const CAST_RANGE := 800000
const CAST_STEP := 2000
const DEATH_TICKS := 30
const PLAYER_W := 30000
const PLAYER_H := 32000
const HAZARD_INSET := 4000
const RING_DEPTH := 8000
const RING_INSET := 4000
const SPIKE_INSET := 4000
