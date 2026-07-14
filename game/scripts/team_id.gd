class_name TeamId

## Shared team identifiers and pitch attack conventions.
## Scoring is based on which goal the ball enters (own goals are intentional).

const HOME: int = 0
const AWAY: int = 1

## HOME attacks the south goal (+Z). Entering the south net credits HOME.
const HOME_ATTACK_DIRECTION: Vector3 = Vector3(0.0, 0.0, 1.0)
const HOME_ATTACK_GOAL_Z: float = 7.5

## AWAY attacks the north goal (-Z). Entering the north net credits AWAY.
const AWAY_ATTACK_DIRECTION: Vector3 = Vector3(0.0, 0.0, -1.0)
const AWAY_ATTACK_GOAL_Z: float = -7.5


static func attack_direction(team: int) -> Vector3:
	if team == AWAY:
		return AWAY_ATTACK_DIRECTION
	return HOME_ATTACK_DIRECTION


static func defend_goal_z(team: int) -> float:
	# Goal this team defends (opposite of their attack).
	if team == AWAY:
		return HOME_ATTACK_GOAL_Z
	return AWAY_ATTACK_GOAL_Z
