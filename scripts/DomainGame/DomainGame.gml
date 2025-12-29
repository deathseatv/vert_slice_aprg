function DomainGame(_eventbus, _procgen) constructor {
    // Create an explicit reference that will not change
    var domain = self;

    domain.eb = _eventbus;
    domain.pg = _procgen;

    domain.seed = 0;
    domain.level = undefined;
    domain.player = { x: 0, y: 0, vx: 0, vy: 0 };
    domain._packets = [];

	move_queue = [];   // array of {x,y}
	move_active = false;
	move_target = undefined;

	enemies = [];
	_enemy_next_id = 1;


    domain.world_query = {
        parent: domain,

        get_player_pos: function() {
            var d = self.parent;
            return { x: d.player.x, y: d.player.y };
        },

        get_seed: function() {
            return self.parent.seed;
        }
    };

    domain.actions = {
        parent: domain,

        start_game: function(_seed) {
            var d = self.parent;

            d.seed = _seed;

            var bp = d.pg.generate_blueprint(d.seed);
            bp = d.pg.validate_repair(bp);

            d.level = { w: bp.w, h: bp.h, seed: bp.seed };

            d.player.x = (bp.w * 16);
            d.player.y = (bp.h * 16);
            d.player.vx = 0;
            d.player.vy = 0;

			d.enemies = [];
			d._enemy_next_id = 1;


            d.eb.publish("domain:started", { seed: d.seed });
        },

		step_simulation: function(_dt) {
		    var d = self.parent;

		    // --- Player step (unchanged logic, but no early returns) ---
		    if (d.move_active) {
		        if (array_length(d.move_queue) <= 0) {
		            d.move_active = false;
		        } else {
		            var wp = d.move_queue[0];
		            var dx = wp.x - d.player.x;
		            var dy = wp.y - d.player.y;

		            var dist = point_distance(d.player.x, d.player.y, wp.x, wp.y);

		            var _speed = 120; // pixels per second
		            var step = _speed * _dt;

		            if (dist <= 1) {
		                d.player.x = wp.x;
		                d.player.y = wp.y;
		                array_delete(d.move_queue, 0, 1);

		                if (array_length(d.move_queue) <= 0) {
		                    d.move_active = false;
		                }
		            } else {
		                var nx = dx / dist;
		                var ny = dy / dist;

		                var adv = min(step, dist);
		                d.player.x += nx * adv;
		                d.player.y += ny * adv;
		            }
		        }
		    }

		    // --- Enemy AI step ---
		    enemyai_step_all(d, _dt);
		},

		set_move_target: function(_wx, _wy) {
		    var d = self.parent;

		    // Queue structure supports future A* waypoints
		    d.move_queue = [];
		    array_push(d.move_queue, { x: _wx, y: _wy });
		    d.move_active = true;
		    d.move_target = { x: _wx, y: _wy };

		    d.eb.publish("domain:move_target", { x: _wx, y: _wy });
		},
		
		spawn_enemy: function(_wx, _wy) {
		    var d = self.parent;

		    var st = tileutil_world_to_tile(_wx, _wy);

		    var e = {
		        id: d._enemy_next_id,

		        // world position (pixels)
		        x: _wx,
		        y: _wy,

		        // immutable spawn tile
		        spawn_tile: { x: st.x, y: st.y },

		        // ai state
		        state: ENEMY_STATE_PATROL,
		        target_tile: undefined,

		        // path
		        path_tiles: [],
		        path_i: 0,

		        // tuning
		        move_speed: ENEMY_SPEED,
		        patrol_radius: ENEMY_PATROL_RADIUS,
		        patrol_pause_t: random_range(ENEMY_PATROL_PAUSE_MIN_S, ENEMY_PATROL_PAUSE_MAX_S),

		        // chase replanning
		        chase_repath_t: 0,
		        last_player_tx: -9999,
		        last_player_ty: -9999
		    };

		    d._enemy_next_id += 1;
		    array_push(d.enemies, e);

		    d.eb.publish("domain:enemy_spawned", { id: e.id, x: e.x, y: e.y });
		}
    };

    domain.snapshot = {
        parent: domain,

        make_character: function() {
            var d = self.parent;
            return {
                version: 1,
                seed: d.seed,
                player: { x: d.player.x, y: d.player.y }
            };
        },

        apply_character: function(_char) {
            var d = self.parent;

            if (!is_struct(_char)) return false;
            if (_char.seed == undefined) return false;

            d.actions.start_game(_char.seed);

            if (is_struct(_char.player)) {
                if (_char.player.x != undefined) d.player.x = _char.player.x;
                if (_char.player.y != undefined) d.player.y = _char.player.y;
            }

            d.eb.publish("domain:loaded", { seed: d.seed });
            return true;
        }
    };

    domain.render_data = {
        parent: domain,
        get_packets: function() { return self.parent._packets; }
    };

    domain.navigation = {
        parent: domain,
        can_walk: function(_x, _y) { return true; }
    };

	build_render_packets = function() {
	    self._packets = [];

	    if (is_struct(self.level)) {
	        var step = 32;
	        for (var yy = 0; yy <= self.level.h * step; yy += step) {
	            for (var xx = 0; xx <= self.level.w * step; xx += step) {
	                array_push(self._packets, { kind: "tile", wx: xx + 16, wy: yy + 16, depth_key: yy });
	            }
	        }
	    }
		
		if (is_struct(move_target)) {
		    array_push(self._packets, {
		        kind: "target",
		        wx: move_target.x,
		        wy: move_target.y,
		        depth_key: move_target.y + 2
		    });
		}
		
	    array_push(self._packets, { kind: "player", wx: self.player.x, wy: self.player.y, depth_key: self.player.y + 1 });
				// enemies
		var n = array_length(self.enemies);
		for (var i = 0; i < n; i++) {
		    var e = self.enemies[i];
		    array_push(self._packets, {
		        kind: "enemy",
		        wx: e.x,
		        wy: e.y,
		        depth_key: e.y + 3
		    });
		}

	};

}
