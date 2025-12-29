// scripts/Macros/Macros.gml
#macro ORTHO_TILE 32
#macro ISO_HALF_W 64 * 0.5  // 32
#macro ISO_HALF_H 31 * 0.5

// Enemy AI
#macro ENEMY_STATE_PATROL 0
#macro ENEMY_STATE_CHASE  1
#macro ENEMY_STATE_RETURN 2
#macro ENEMY_STATE_DEAD   3

#macro ENEMY_SPEED              90     // player is 120 in DomainGame
#macro ENEMY_PATROL_RADIUS      3
#macro ENEMY_PATROL_PAUSE_MIN_S 2.00
#macro ENEMY_PATROL_PAUSE_MAX_S 6.00
#macro ENEMY_CHASE_REPATH_S     0.20   // seconds

// Combat tuning (tiles/pixels + seconds)
#macro COMBAT_MELEE_RANGE_TILES 1
#macro COMBAT_MELEE_RANGE_PX    (ORTHO_TILE * COMBAT_MELEE_RANGE_TILES)
#macro COMBAT_AGGRO_RANGE_TILES 3
#macro COMBAT_ATTACK_COOLDOWN_S 0.45
#macro COMBAT_ATTACK_WINDUP_S   0.10
#macro COMBAT_HIT_RECOVERY_S    0.20
#macro COMBAT_DAMAGE_MELEE      2

// Unit action/state enums (shared by player + enemies)
#macro ACT_IDLE         0
#macro ACT_MOVE_TO      1
#macro ACT_ATTACK       2
#macro ACT_HIT_RECOVERY 3
#macro ACT_DEAD         4
