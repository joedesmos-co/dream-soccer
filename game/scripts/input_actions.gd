class_name InputActions

## Shared Input Map action names for Dream Soccer.
## Configure bindings in Project Settings -> Input Map (project.godot).
## Gameplay code must use these constants so keyboard and controller stay unified.

# Movement
const MOVE_LEFT := &"move_left"
const MOVE_RIGHT := &"move_right"
const MOVE_FORWARD := &"move_forward"
const MOVE_BACK := &"move_back"
const SPRINT := &"sprint"

# Attacking (reserved — not implemented yet)
const SHORT_PASS := &"short_pass"
const SHOOT := &"shoot"
const THROUGH_BALL := &"through_ball"
const LOB_PASS := &"lob_pass"
const SHIELD_BALL := &"shield_ball"

# Defending (reserved — not implemented yet)
const SWITCH_PLAYER := &"switch_player"
const JOCKEY := &"jockey"

## Godot 4.7 JoyAxis indices (see @GlobalScope JoyAxis enum):
##   0 = JOY_AXIS_LEFT_X, 1 = JOY_AXIS_LEFT_Y
##   2 = JOY_AXIS_RIGHT_X, 3 = JOY_AXIS_RIGHT_Y  (reserved, unbound)
##   4 = JOY_AXIS_TRIGGER_LEFT (LT / L2)
##   5 = JOY_AXIS_TRIGGER_RIGHT (RT / R2)
##
## Godot 4.7 JoyButton indices (see @GlobalScope JoyButton enum):
##   0 = A / Cross, 1 = B / Circle, 2 = X / Square, 3 = Y / Triangle
##   9 = LB / L1
