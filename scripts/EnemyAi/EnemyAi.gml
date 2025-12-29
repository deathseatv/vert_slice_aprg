function enemyai_set_state(_e, _new_state) {
    _e.state = _new_state;

    // clear path on state change
    _e.path_tiles = [];
    _e.path_i = 0;
    _e.target_tile = undefined;

	if (_new_state == ENEMY_STATE_PATROL) {
	    _e.patrol_pause_t = random_range(ENEMY_PATROL_PAUSE_MIN_S, ENEMY_PATROL_PAUSE_MAX_S);
	}
	else if (_new_state == ENEMY_STATE_CHASE) {
	    _e.chase_repath_t = 0;
	    _e.last_player_tx = -9999;
	    _e.last_player_ty = -9999;
	} 
	else {
	_e.patrol_pause_t = 0; // no pausing in CHASE/RETURN
	}
}

function enemyai_pick_patrol_target(_d, _e) {
    var lvl = _d.level;
    var nav = _d.navigation;

    var r = _e.patrol_radius;
    for (var tries = 0; tries < 24; tries++) {
        var ox = irandom_range(-r, r);
        var oy = irandom_range(-r, r);

        var tx = _e.spawn_tile.x + ox;
        var ty = _e.spawn_tile.y + oy;

        if (!tileutil_in_bounds(lvl, tx, ty)) continue;
        if (!nav.can_walk(tx, ty)) continue;

        return { x: tx, y: ty };
    }

    return { x: _e.spawn_tile.x, y: _e.spawn_tile.y };
}

function enemyai_move_along_path(_e, _dt) {
    if (!is_array(_e.path_tiles)) return;
    if (_e.path_i >= array_length(_e.path_tiles)) return;

    var t = _e.path_tiles[_e.path_i];
    var wp = tileutil_tile_to_world_center(t.x, t.y);

    var dx = wp.x - _e.x;
    var dy = wp.y - _e.y;
    var dist = point_distance(_e.x, _e.y, wp.x, wp.y);

    var step = _e.move_speed * _dt;

    if (dist <= 1) {
        _e.x = wp.x;
        _e.y = wp.y;
        _e.path_i += 1;
        return;
    }

    var nx = dx / dist;
    var ny = dy / dist;

    var adv = min(step, dist);
    _e.x += nx * adv;
    _e.y += ny * adv;
}

function enemyai_repath_to_tile(_d, _e, _goal_tx, _goal_ty) {
    var lvl = _d.level;
    var nav = _d.navigation;

    var et = tileutil_world_to_tile(_e.x, _e.y);

    var p = nav_astar_tiles(nav, lvl, et.x, et.y, _goal_tx, _goal_ty);
    if (p == undefined) {
        _e.path_tiles = [];
        _e.path_i = 0;
        _e.target_tile = undefined;
        return false;
    }

    _e.path_tiles = p;
    _e.path_i = 0;
    _e.target_tile = { x: _goal_tx, y: _goal_ty };
    return true;
}

function enemyai_step_all(_d, _dt) {
    if (!is_struct(_d.level)) return;

    var pt = tileutil_world_to_tile(_d.player.x, _d.player.y);

    var n = array_length(_d.enemies);
    for (var i = 0; i < n; i++) {
        var e = _d.enemies[i];

        var et = tileutil_world_to_tile(e.x, e.y);
        var dist_tp = tileutil_dist_chebyshev(et.x, et.y, pt.x, pt.y);

        if (e.state == ENEMY_STATE_PATROL) {
            if (dist_tp <= 2) {
                enemyai_set_state(e, ENEMY_STATE_CHASE);
            } else {
                // PATROL: pause 2–6s between moves
				var path_len = (is_array(e.path_tiles)) ? array_length(e.path_tiles) : 0;
				var path_done = (path_len == 0) || (e.path_i >= path_len);

				if (!path_done) {
				    // moving to patrol target
				    enemyai_move_along_path(e, _dt);

				    // if we just finished this step, start the pause
				    path_len = (is_array(e.path_tiles)) ? array_length(e.path_tiles) : 0;
				    path_done = (path_len == 0) || (e.path_i >= path_len);
				    if (path_done) {
				        e.patrol_pause_t = random_range(ENEMY_PATROL_PAUSE_MIN_S, ENEMY_PATROL_PAUSE_MAX_S);
				    }
				} else {
				    // idle pause before choosing next patrol point
				    if (e.patrol_pause_t <= 0) {
				        e.patrol_pause_t = random_range(ENEMY_PATROL_PAUSE_MIN_S, ENEMY_PATROL_PAUSE_MAX_S);
				    }

				    e.patrol_pause_t -= _dt;

				    if (e.patrol_pause_t <= 0) {
				        var tgt = enemyai_pick_patrol_target(_d, e);
				        enemyai_repath_to_tile(_d, e, tgt.x, tgt.y);
				        // movement begins next tick (keeps the pause clean)
				    }
				}

            }
        }
        else if (e.state == ENEMY_STATE_CHASE) {
            if (dist_tp > 3) {
                enemyai_set_state(e, ENEMY_STATE_RETURN);
            } else {
                e.chase_repath_t -= _dt;

                // repath if cooldown expired OR player changed tiles
                if (e.chase_repath_t <= 0 || e.last_player_tx != pt.x || e.last_player_ty != pt.y) {
                    enemyai_repath_to_tile(_d, e, pt.x, pt.y);
                    e.chase_repath_t = ENEMY_CHASE_REPATH_S;
                    e.last_player_tx = pt.x;
                    e.last_player_ty = pt.y;
                }

                enemyai_move_along_path(e, _dt);
            }
        }
        else if (e.state == ENEMY_STATE_RETURN) {
            var sx = e.spawn_tile.x;
            var sy = e.spawn_tile.y;

            if (et.x == sx && et.y == sy) {
                enemyai_set_state(e, ENEMY_STATE_PATROL);
            } else {
                var needs_path = true;

                if (is_struct(e.target_tile)) {
                    if (e.target_tile.x == sx && e.target_tile.y == sy) {
                        // still returning; only repath if path exhausted
                        needs_path = (e.path_i >= array_length(e.path_tiles));
                    }
                }

                if (needs_path) {
                    enemyai_repath_to_tile(_d, e, sx, sy);
                }

                enemyai_move_along_path(e, _dt);
            }
        }

        // write-back not required for structs, but safe if later swapped
        _d.enemies[i] = e;
    }
}
