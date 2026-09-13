extends Resource
class_name MageFlightProfile
## Tunable "game feel" levers for PlayerMage. Defaults reproduce the original hard-coded values.
## Presets live in res://player/mage/profiles/.

@export var display_name := "Default"

@export_group("Speed")
@export var max_speed := 80.0 ## Boost ceiling.
@export var min_speed := 20.0 ## Brake floor.
@export var base_speed := 50.0 ## Cruise speed when neither boosting nor braking.
@export var acceleration := 15.5 ## m/s² toward max_speed / back up to base_speed.
@export var deceleration := 10.5 ## m/s² toward min_speed / back down to base_speed.
@export var boost_mana_per_second := 20.0

@export_group("Turning")
@export var yaw_speed := 45.0
@export var pitch_speed := 45.0
@export var roll_speed := 45.0

@export_group("Feel")
## How quickly angular velocity ramps to the stick target. 60 = no smoothing (instant), ~4 = heavy/airplane.
@export_range(1.0, 60.0) var turn_responsiveness := 60.0
## Fraction of turn rate lost at max_speed. 0 = turning is speed independent.
@export_range(0.0, 1.0) var high_speed_turn_penalty := 0.0
## 0 = velocity always follows facing (on rails). Higher = velocity lags facing, so you slide through turns.
@export_range(0.0, 1.0) var drift := 0.0
## Roll back toward level with the horizon, degrees/sec, whenever there is no stick input. 0 = off.
@export_range(0.0, 360.0) var auto_level_speed := 0.0
## Cosmetic lean of the mesh when yawing.
@export var mesh_lean_degrees := 45.0
@export var mesh_lean_speed := 1.0

func yaw_rad() -> float:
	return deg_to_rad(yaw_speed)

func pitch_rad() -> float:
	return deg_to_rad(pitch_speed)

func roll_rad() -> float:
	return deg_to_rad(roll_speed)

## Rate at which velocity direction slerps toward facing, per second. Only used when drift > 0.
func drift_follow_rate() -> float:
	return lerpf(30.0, 3.0, drift)
