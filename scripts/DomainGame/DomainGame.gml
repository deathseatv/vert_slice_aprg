// ================================
// FILE: scripts/DomainGame/DomainGame.gml
// REPLACE ENTIRE FILE WITH THIS
// ================================
// scripts/DomainGame/DomainGame.gml
function DomainGame(_eventbus, _procgen) constructor {
    // Create an explicit reference that will not change
    var domain = self;

    domain.eb = _eventbus;
    domain.pg = _procgen;

    domain.seed = 0;
    domain.level = undefined;

    // Player domain data
    domain.player = {
        x: 0, y: 0, vx: 0, vy: 0,
        hp: 100, hp_max: 100,

        // combat core
        act: ACT_IDLE,
        act_target_id: -1,
        atk_cd_t: 0,
        hitrec_t: 0,

        // single-swing intent + hold
        attack_cmd: false,     // one-shot request (consumed on swing start)
        attack_hold: false,    // true while LMB held on current target

        // single-slot queued order (no stack)
        queued_attack_cmd: false,
        queued_target_id: -1,

        // attack windup (interrupt can cancel)
        swing_active: false,
        swing_t: 0,
        swing_target_id: -1,

        // inventory (persists during play session)
        inventory: [],

        // item pickup intent (click -> move -> autopick)
        pickup_target_item_id: -1
    };

    // inventory UI state (toggle with I, close with Esc)
    domain.inventory_open = false;
// inventory UI widget state (icon column + drag scroll + carry)
domain.inv_scroll_offset_px = 0;
domain.inv_drag_active = false;
domain.inv_drag_start_mouse_y = 0;
domain.inv_drag_start_scroll_offset = 0;
domain.inv_drag_threshold_px = 6;

domain.carry_active = false;
domain.carry_item = undefined;
domain.carry_original_index = -1;


    domain._packets = [];

    // player movement queue (world points)
    move_queue = [];   // array of {x,y}
    move_active = false;
    move_target = undefined;

    enemies = [];
    _enemy_next_id = 1;


    _inv_uid_next = 1; // unique ids for inventory entries
    // world items
    items = [];
    _item_next_id = 1;

    // ----------------------------
    // Phase 2: Domain invariant gate
    // ----------------------------
    // Safe to call every frame; only assigns when something is missing/wrong.
    // Goal: prevent "field not set before reading" crashes at the source.
    invariants_check = function() {
        var d = self;

        // Ensure root collections
        if (!is_array(d.items)) d.items = [];
        if (!is_array(d.enemies)) d.enemies = [];

        // Ensure player struct exists (minimal fallback)
        if (!is_struct(d.player)) {
            d.player = {
                x: 0, y: 0, vx: 0, vy: 0,
                hp: 100, hp_max: 100,
                act: ACT_IDLE,
                act_target_id: -1,
                atk_cd_t: 0,
                hitrec_t: 0,
                attack_cmd: false,
                attack_hold: false,
                queued_attack_cmd: false,
                queued_target_id: -1,
                swing_active: false,
                swing_t: 0,
                swing_target_id: -1,
                inventory: [],
                // equipment (Phase 6)
                equipment: { weapon: undefined },
                pickup_target_item_id: -1
            };
        } else {
            // Ensure player.inventory exists and is an array
            if (!is_array(d.player.inventory)) d.player.inventory = [];

            // Ensure player equipment slot struct exists
            if (!variable_struct_exists(d.player, "equipment") || !is_struct(d.player.equipment)) {
                d.player.equipment = { weapon: undefined };
            } else {
                if (!variable_struct_exists(d.player.equipment, "weapon")) d.player.equipment.weapon = undefined;
            }

            // Ensure inventory entry uids exist (assigned lazily)
            if (!variable_struct_exists(d, "_inv_uid_next") || d._inv_uid_next == undefined) d._inv_uid_next = 1;
            if (is_array(d.player.inventory)) {
                var _ninv = array_length(d.player.inventory);
                for (var _ii = 0; _ii < _ninv; _ii++) {
                    var _it = d.player.inventory[_ii];
                    if (is_struct(_it)) {
                        if (!variable_struct_exists(_it, "uid") || _it.uid == undefined) {
                            _it.uid = d._inv_uid_next;
                            d._inv_uid_next += 1;
                            d.player.inventory[_ii] = _it;
                        }
                    } else {
                        // normalize non-struct entries
                        d.player.inventory[_ii] = { name: string(_it), uid: d._inv_uid_next };
                        d._inv_uid_next += 1;
                    }
                }
            }
        }

        // Inventory UI state relied on by UI/input
        if (!is_bool(d.inventory_open)) d.inventory_open = false;
        if (!is_real(d.inv_scroll_offset_px)) d.inv_scroll_offset_px = 0;
        if (!is_bool(d.inv_drag_active)) d.inv_drag_active = false;
        if (!is_real(d.inv_drag_start_mouse_y)) d.inv_drag_start_mouse_y = 0;
        if (!is_real(d.inv_drag_start_scroll_offset)) d.inv_drag_start_scroll_offset = d.inv_scroll_offset_px;
        if (!is_real(d.inv_drag_threshold_px)) d.inv_drag_threshold_px = 6;

        if (!is_bool(d.carry_active)) d.carry_active = false;
        if (!variable_struct_exists(d, "carry_item")) d.carry_item = undefined;
        if (!is_real(d.carry_original_index)) d.carry_original_index = -1;

        // Core movement fields
        if (!is_array(d.move_queue)) d.move_queue = [];
        if (!is_bool(d.move_active)) d.move_active = false;
        if (!variable_struct_exists(d, "move_target")) d.move_target = undefined;
    };

    // ----------------------------
    // Helpers (items)
    // ----------------------------
    function domain_item_find_index_by_id(_d, _id) {
        var n = array_length(_d.items);
        for (var i = 0; i < n; i++) {
            if (_d.items[i].id == _id) return i;
        }
        return -1;
    }

    function domain_item_remove_at(_d, _idx) {
        if (_idx < 0) return;
        array_delete(_d.items, _idx, 1);
    }

    function domain_player_clear_pickup_intent(_d) {
        _d.player.pickup_target_item_id = -1;
    }

    // Build a move queue from A* tile path
    function domain_set_player_path_from_tiles(_d, _tiles) {
        _d.move_queue = [];
        if (!is_array(_tiles) || array_length(_tiles) <= 0) {
            _d.move_active = false;
            _d.move_target = undefined;
            return;
        }

        for (var i = 0; i < array_length(_tiles); i++) {
            var t = _tiles[i];
            var wp = tileutil_tile_to_world_center(t.x, t.y);
            array_push(_d.move_queue, { x: wp.x, y: wp.y });
        }

        _d.move_active = true;
        var last = _d.move_queue[array_length(_d.move_queue) - 1];
        _d.move_target = { x: last.x, y: last.y };
    }

    // Convenience: set path to a goal tile using NavAStar
    function domain_player_pathfind_to_tile(_d, _goal_tx, _goal_ty) {
        var lvl = _d.level;
        var nav = _d.navigation;
        if (!is_struct(lvl)) return false;

        var pt = tileutil_world_to_tile(_d.player.x, _d.player.y);
        var path = nav_astar_tiles(nav, lvl, pt.x, pt.y, _goal_tx, _goal_ty);
        if (path == undefined) return false;

        domain_set_player_path_from_tiles(_d, path);
        return true;
    }

    /// Returns true if any unpicked world item occupies tile (_tx,_ty).
    /// Only reads from the passed-in array; does not capture domain state.
    function domain_tile_has_unpicked_item_on_tile(_items, _tx, _ty) {
        var n = array_length(_items);
        for (var i = 0; i < n; i++) {
            var it = _items[i];
            if (it.picked) continue;

            var t2 = tileutil_world_to_nearest_tile(it.x, it.y);
            if (t2.x == _tx && t2.y == _ty) return true;
        }
        return false;
    }

    /// Finds the nearest unoccupied tile to (_start_tx,_start_ty) using Chebyshev rings.
    /// "Unoccupied" means no unpicked world item already on that tile.
    /// Returns { x: tx, y: ty }.
    function domain_find_nearest_unoccupied_tile(_items, _lvl, _start_tx, _start_ty, _max_r) {
        var start_tx = _start_tx;
        var start_ty = _start_ty;

        if (is_struct(_lvl)) {
            start_tx = clamp(start_tx, 0, _lvl.w - 1);
            start_ty = clamp(start_ty, 0, _lvl.h - 1);
        }

        // Fast path
        if (!domain_tile_has_unpicked_item_on_tile(_items, start_tx, start_ty)) {
            return { x: start_tx, y: start_ty };
        }

        var max_r = max(0, floor(_max_r));
        for (var r = 1; r <= max_r; r++) {
            for (var dy = -r; dy <= r; dy++) {
                for (var dx = -r; dx <= r; dx++) {
                    if (max(abs(dx), abs(dy)) != r) continue;

                    var tx = start_tx + dx;
                    var ty = start_ty + dy;

                    if (is_struct(_lvl)) {
                        if (tx < 0 || ty < 0 || tx >= _lvl.w || ty >= _lvl.h) continue;
                    }

                    if (!domain_tile_has_unpicked_item_on_tile(_items, tx, ty)) {
                        return { x: tx, y: ty };
                    }
                }
            }
        }

        // Fallback: return start tile even if occupied
        return { x: start_tx, y: start_ty };
    }

    // ----------------------------
    // Ports
    // ----------------------------
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

            // HP init
            d.player.hp_max = 100;
            d.player.hp = d.player.hp_max;

            // Combat init
            d.player.act = ACT_IDLE;
            d.player.act_target_id = -1;
            d.player.atk_cd_t = 0;
            d.player.hitrec_t = 0;

            d.player.attack_cmd = false;
            d.player.attack_hold = false;

            d.player.queued_attack_cmd = false;
            d.player.queued_target_id = -1;

            d.player.swing_active = false;
            d.player.swing_t = 0;
            d.player.swing_target_id = -1;

            // Inventory init
            d.player.inventory = [];
            d.player.pickup_target_item_id = -1;
            d.inventory_open = false;
// UI state init
d.inv_scroll_offset_px = 0;
d.inv_drag_active = false;
d.inv_drag_start_mouse_y = 0;
d.inv_drag_start_scroll_offset = 0;
d.inv_drag_threshold_px = 6;

d.carry_active = false;
d.carry_item = undefined;
d.carry_original_index = -1;


            // Items init
            d.items = [];
            d._item_next_id = 1;

            d.enemies = [];
            d._enemy_next_id = 1;

            d.eb.publish("domain:started", { seed: d.seed });
        },

        // Spawn "rusty sword" on nearest tile center to (_wx,_wy)
// (legacy helper kept for compatibility)
spawn_item_drop_rusty_sword: function(_wx, _wy) {
    self.spawn_item_drop_named("rusty sword", _wx, _wy);
},

// Spawn an item with name on nearest tile center to (_wx,_wy)
spawn_item_drop_named: function(_name, _wx, _wy) {
    var d = self.parent;

    var lvl = d.level;

    // Ensure items storage exists
    if (!variable_struct_exists(d, "items") || !is_array(d.items)) d.items = [];
    if (!variable_struct_exists(d, "_item_next_id")) d._item_next_id = 1;

    var nt = tileutil_world_to_nearest_tile(_wx, _wy);
    var tx = nt.x;
    var ty = nt.y;

    // clamp to bounds if possible
    if (is_struct(lvl)) {
        tx = clamp(tx, 0, lvl.w - 1);
        ty = clamp(ty, 0, lvl.h - 1);
    }

    var c = tileutil_tile_to_world_center(tx, ty);

    var it = {
        id: d._item_next_id,
        name: _name,
        x: c.x,
        y: c.y,
        picked: false
    };

    d._item_next_id += 1;
    array_push(d.items, it);

    d.eb.publish("domain:item_spawned", { id: it.id, name: it.name, x: it.x, y: it.y });
    return it.id;
},

// Drop an item on the tile under the given world position.
// If _avoid_overlap is true, performs an explicit occupancy check against the items array
// and finds the nearest free tile (Chebyshev rings) if the cursor tile is occupied.
spawn_item_drop_at_world_named: function(_name, _wx, _wy, _avoid_overlap) {
    var d = self.parent;

    if (_avoid_overlap == undefined) _avoid_overlap = true;

    // Ensure items storage exists
    if (!variable_struct_exists(d, "items") || !is_array(d.items)) d.items = [];
    if (!variable_struct_exists(d, "_item_next_id")) d._item_next_id = 1;

    var lvl = d.level;
    var nt = tileutil_world_to_nearest_tile(_wx, _wy);
    var tx = nt.x;
    var ty = nt.y;

    if (is_struct(lvl)) {
        tx = clamp(tx, 0, lvl.w - 1);
        ty = clamp(ty, 0, lvl.h - 1);
    }

    if (_avoid_overlap) {
        var items_arr = d.items;
        var best = domain_find_nearest_unoccupied_tile(items_arr, lvl, tx, ty, 32);
        tx = best.x;
        ty = best.y;
    }

    var c = tileutil_tile_to_world_center(tx, ty);
    return self.spawn_item_drop_named(_name, c.x, c.y);
},

// Drop an item near the player: nearest unoccupied tile to player (Chebyshev rings).
// Unoccupied means: no unpicked world item already on that tile.
spawn_item_drop_near_player_named: function(_name) {
    var d = self.parent;

    // Ensure items storage exists
    if (!variable_struct_exists(d, "items") || !is_array(d.items)) d.items = [];
    if (!variable_struct_exists(d, "_item_next_id")) d._item_next_id = 1;

    var lvl = d.level;

    var pt = tileutil_world_to_nearest_tile(d.player.x, d.player.y);
    var start_tx = pt.x;
    var start_ty = pt.y;

    // Find nearest unoccupied tile around player tile (ring search), explicit args.
    var items_arr = d.items;
    var best = domain_find_nearest_unoccupied_tile(items_arr, lvl, start_tx, start_ty, 32);
    var c = tileutil_tile_to_world_center(best.x, best.y);

    var it = {
        id: d._item_next_id,
        name: _name,
        x: c.x,
        y: c.y,
        picked: false
    };

    d._item_next_id += 1;
    array_push(d.items, it);

    d.eb.publish("domain:item_spawned", { id: it.id, name: it.name, x: it.x, y: it.y });
    return it.id;
},

// Give items to player inventory (no stacking): adds 'count' separate entries.
// Accepts item tokens like: rusty_sword, rusty sword, RustySword.
give_player_items: function(_item_token, _count) {
    var d = self.parent;

    if (!is_array(d.player.inventory)) d.player.inventory = [];

    var count = max(0, floor(_count));
    if (count <= 0) return 0;

    var tok = string_lower(string(_item_token));
    tok = string_replace_all(tok, "_", " ");
    tok = string_replace_all(tok, "-", " ");

    // Basic CamelCase -> spaced (RustySword -> rusty sword)
    if (string_count(" ", tok) == 0) {
        var s = string(_item_token);
        var out = "";
        var len = string_length(s);
        for (var i = 1; i <= len; i++) {
            var ch = string_char_at(s, i);
            var is_upper = (ch >= "A" && ch <= "Z");
            if (i > 1 && is_upper) out += " ";
            out += ch;
        }
        tok = string_lower(out);
    }

    tok = string_trim(tok);
    if (tok == "rustysword") tok = "rusty sword";

    for (var k = 0; k < count; k++) {
        array_push(d.player.inventory, { name: tok, uid: d._inv_uid_next });
        d._inv_uid_next += 1;
    }

    d.eb.publish("domain:inventory_changed", { added: tok, count: count });
    return count;
},

// Equip an inventory entry into the weapon slot.
// _item_token: string name
// _index: optional inventory index to disambiguate duplicates
// _toggle: if true, equips if not equipped; unequips if currently equipped and matches
equip_item_named: function(_item_token, _index, _toggle) {
    var d = self.parent;
    d.invariants_check();

    var tok = string_lower(string(_item_token));
    tok = string_replace_all(tok, "_", " ");
    tok = string_replace_all(tok, "-", " ");
    tok = string_trim(tok);

    // ensure equipment exists
    if (!is_struct(d.player.equipment)) d.player.equipment = { weapon: undefined };

    // Toggle off if currently equipped and matches token (best-effort)
    if (_toggle) {
        var w = d.player.equipment.weapon;
        if (is_struct(w) && w.name != undefined) {
            var wn = string_lower(string(w.name));
            if (wn == tok) {
                return self.unequip_item_named(tok);
            }
        }
    }

    var inv = d.player.inventory;
    if (!is_array(inv) || array_length(inv) <= 0) return false;

    var pick_i = -1;

    // Prefer exact index if provided and matches
    if (_index != undefined) {
        var ii = floor(_index);
        if (ii >= 0 && ii < array_length(inv)) {
            var cand = inv[ii];
            var cn = (is_struct(cand) && cand.name != undefined) ? string_lower(string(cand.name)) : string_lower(string(cand));
            if (cn == tok) pick_i = ii;
        }
    }

    // Fallback: first matching name
    if (pick_i < 0) {
        for (var i = 0; i < array_length(inv); i++) {
            var it = inv[i];
            var nm = (is_struct(it) && it.name != undefined) ? string_lower(string(it.name)) : string_lower(string(it));
            if (nm == tok) { pick_i = i; break; }
        }
    }

    if (pick_i < 0) return false;

    var item = inv[pick_i];
    array_delete(inv, pick_i, 1);
    d.player.inventory = inv;

    // If slot occupied, unequip current weapon back into inventory (append)
    if (is_struct(d.player.equipment.weapon)) {
        array_push(d.player.inventory, d.player.equipment.weapon);
    }

    if (!is_struct(item)) item = { name: string(item) };
    // ensure uid
    if (!variable_struct_exists(item, "uid") || item.uid == undefined) {
        item.uid = d._inv_uid_next;
        d._inv_uid_next += 1;
    }

    d.player.equipment.weapon = item;

    d.eb.publish("domain:equipment_changed", { slot: "weapon", name: item.name, uid: item.uid });
    d.eb.publish("domain:inventory_changed", { equipped: item.name });

    return true;
},

// Unequip weapon back into inventory. If _name provided, only unequip if it matches.
unequip_item_named: function(_name) {
    var d = self.parent;
    d.invariants_check();

    if (!is_struct(d.player.equipment)) d.player.equipment = { weapon: undefined };

    var w = d.player.equipment.weapon;
    if (!is_struct(w)) return false;

    if (_name != undefined) {
        var tok = string_lower(string(_name));
        tok = string_replace_all(tok, "_", " ");
        tok = string_replace_all(tok, "-", " ");
        tok = string_trim(tok);

        var wn = (w.name != undefined) ? string_lower(string(w.name)) : "";
        if (wn != tok) return false;
    }

    array_push(d.player.inventory, w);
    d.player.equipment.weapon = undefined;

    d.eb.publish("domain:equipment_changed", { slot: "weapon", name: undefined });
    d.eb.publish("domain:inventory_changed", { unequipped: true });

    return true;
},


        // Begin pickup flow for an item id: immediate if in range else pathfind + auto pickup
        player_try_pickup_item: function(_item_id) {
            var d = self.parent;

            var idx = domain_item_find_index_by_id(d, _item_id);
            if (idx < 0) return false;

            var it = d.items[idx];
            if (it.picked) return false;

            // Cancel combat orders (clicking item is not an attack)
            d.player.act_target_id = -1;
            d.player.attack_cmd = false;
            d.player.attack_hold = false;
            d.player.queued_attack_cmd = false;
            d.player.queued_target_id = -1;
            d.player.swing_active = false;
            d.player.swing_t = 0;
            d.player.swing_target_id = -1;

            var in_range = point_distance(d.player.x, d.player.y, it.x, it.y) <= COMBAT_MELEE_RANGE_PX;

            if (in_range) {
                // immediate pickup
                it.picked = true;
                d.items[idx] = it;

                array_push(d.player.inventory, { name: it.name, uid: it.id });

                domain_item_remove_at(d, idx);
                domain_player_clear_pickup_intent(d);

                d.eb.publish("domain:item_picked", { name: it.name });
                return true;
            }

            // Out of range: set pickup intent + pathfind to item tile
            d.player.pickup_target_item_id = _item_id;

            var goal = tileutil_world_to_tile(it.x, it.y);
            var ok = domain_player_pathfind_to_tile(d, goal.x, goal.y);

            if (!ok) {
                // Fallback: direct move target if A* fails (should not happen with can_walk=true)
                d.actions.set_move_target(it.x, it.y);
            }

            return true;
        },

        // Called every step to complete auto-pickup when entering range
        step_item_pickup_intent: function() {
            var d = self.parent;

            var _id = d.player.pickup_target_item_id;
            if (_id < 0) return;

            var idx = domain_item_find_index_by_id(d, _id);
            if (idx < 0) {
                domain_player_clear_pickup_intent(d);
                return;
            }

            var it = d.items[idx];
            if (it.picked) {
                domain_player_clear_pickup_intent(d);
                return;
            }

            var in_range = point_distance(d.player.x, d.player.y, it.x, it.y) <= COMBAT_MELEE_RANGE_PX;
            if (!in_range) return;

            // Auto-pickup on entering range
            it.picked = true;
            d.items[idx] = it;

            array_push(d.player.inventory, { name: it.name });

            domain_item_remove_at(d, idx);
            domain_player_clear_pickup_intent(d);

            // Stop movement once picked up (prevents overshooting / continued path)
            d.move_queue = [];
            d.move_active = false;
            d.move_target = undefined;

            d.eb.publish("domain:item_picked", { name: it.name });
        },

        step_simulation: function(_dt) {
            var d = self.parent;

            // --- Enemy combat overlay vs player (can interrupt player) ---
            var en = array_length(d.enemies);
            for (var i = 0; i < en; i++) {
                combat_step_enemy_vs_player(d, d.enemies[i], _dt);
            }

            // --- Player combat intent (may set move target / windup / swing) ---
            combat_step_player(d, _dt);

            // If attacking or recovering, hard-stop movement
            if (d.player.act == ACT_ATTACK || d.player.act == ACT_HIT_RECOVERY) {
                d.move_queue = [];
                d.move_active = false;
            }

            // --- Player movement (disabled during ATTACK/HIT) ---
            if (d.player.act != ACT_ATTACK && d.player.act != ACT_HIT_RECOVERY) {
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
            }

            // --- Item pickup intent resolves AFTER movement ---
            d.actions.step_item_pickup_intent();

            // --- Enemy AI step (must respect ACT_ATTACK/ACT_HIT_RECOVERY/DEAD) ---
            enemyai_step_all(d, _dt);
        },

        set_move_target: function(_wx, _wy) {
            var d = self.parent;

            // Queue structure supports A* waypoints
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

                // HP fields
                hp: 30,
                hp_max: 30,

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
                last_player_ty: -9999,

                // combat
                act: ACT_IDLE,
                act_target_kind: "none", // "player" when engaged
                atk_cd_t: 0,
                hitrec_t: 0,
                damage_melee: COMBAT_DAMAGE_MELEE,

                // attack windup (interrupt can cancel)
                swing_active: false,
                swing_t: 0,

                // item drop flag
                drop_done: false
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

    
    // --- Ensure give_player_items is available on actions (compat / defensive) ---
    if (!variable_struct_exists(domain.actions, "give_player_items")) {
        if (variable_struct_exists(domain.actions, "give_player_items_named") && is_callable(domain.actions.give_player_items_named)) {
            domain.actions.give_player_items = function(_item_token, _count) {
                return self.parent.actions.give_player_items_named(_item_token, _count);
            };
        } else {
            domain.actions.give_player_items = function(_item_token, _count) {
                var d = self.parent;

                if (!variable_struct_exists(d.player, "inventory") || !is_array(d.player.inventory)) d.player.inventory = [];

                var count = max(0, floor(_count));
                if (count <= 0) return 0;

                // Normalize token: underscores -> spaces; insert spaces in CamelCase; lowercase.
                var s = string(_item_token);
                s = string_replace_all(s, "_", " ");
                // CamelCase -> space before caps (best-effort)
                var out = "";
                var i = 1;
                var ch, prev;
                while (i <= string_length(s)) {
                    ch = string_char_at(s, i);
                    if (i > 1) {
                        prev = string_char_at(s, i - 1);
                        if (ord(ch) >= ord("A") && ord(ch) <= ord("Z") && !(ord(prev) >= ord("A") && ord(prev) <= ord("Z")) && prev != " ") {
                            out += " ";
                        }
                    }
                    out += ch;
                    i += 1;
                }
                s = string_lower(string_trim(out));

                // Canonical mapping
                if (s == "rusty sword" || s == "rusty  sword" || s == "rustysword") s = "rusty sword";

                var added = 0;
                repeat (count) {
                    array_push(d.player.inventory, { name: s });
                    added += 1;
                }

                d.eb.publish("domain:inventory_given", { name: s, count: added });
                return added;
            };
        }
    }

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
            for (var ty_px = 0; ty_px <= self.level.h * step; ty_px += step) {
			    for (var tx_px = 0; tx_px <= self.level.w * step; tx_px += step) {
			        array_push(self._packets, {
			            kind: "tile",
			            wx: tx_px + 16,
			            wy: ty_px + 16,
			            depth_key: ty_px
			        });
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

        // items
        var m = array_length(self.items);
        for (var j = 0; j < m; j++) {
            var it = self.items[j];
            if (it == undefined) continue;
            if (it.picked) continue;

            array_push(self._packets, {
                kind: "item",
                wx: it.x,
                wy: it.y,
                name: it.name,
                depth_key: it.y + 2
            });
        }
    };
}
