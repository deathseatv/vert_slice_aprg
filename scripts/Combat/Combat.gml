// ================================
// FILE: scripts/Combat/Combat.gml
// REPLACE ENTIRE FILE WITH THIS
// ================================
// scripts/Combat/Combat.gml
// ------------------------------------------------------------
// Combat helpers + stepping (domain logic; no instances)
// ------------------------------------------------------------

function combat_find_enemy_index_by_id(_d, _id) {
    var n = array_length(_d.enemies);
    for (var i = 0; i < n; i++) {
        if (_d.enemies[i].id == _id) return i;
    }
    return -1;
}

function combat_enemy_die(_d, _e) {
    _e.hp = 0;

    // stop all action permanently
    _e.act = ACT_DEAD;
    _e.state = ENEMY_STATE_DEAD;
    _e.act_target_kind = "none";

    // clear timers/intent
    _e.atk_cd_t = 0;
    _e.hitrec_t = 0;

    // cancel any pending swing
    if (variable_struct_exists(_e, "swing_active")) _e.swing_active = false;
    if (variable_struct_exists(_e, "swing_t")) _e.swing_t = 0;

    // hard-stop movement/pathing data
    _e.path_tiles = [];
    _e.path_i = 0;
    _e.target_tile = undefined;

    // ----------------------------
    // ITEM DROP (exactly once)
    // ----------------------------
    if (_e.drop_done == undefined) _e.drop_done = false;

    if (!_e.drop_done) {
        _e.drop_done = true;

        // Spawn "rusty sword" centered on nearest tile to death position
        if (is_struct(_d) && is_struct(_d.actions) && is_method(_d.actions.spawn_item_drop_rusty_sword)) {
            _d.actions.spawn_item_drop_rusty_sword(_e.x, _e.y);
        }
    }
}

function combat_in_melee_range(_ax, _ay, _bx, _by) {
    return point_distance(_ax, _ay, _bx, _by) <= COMBAT_MELEE_RANGE_PX;
}

function combat_in_aggro_range(_ax, _ay, _bx, _by) {
    // tile-chebyshev to match EnemyAi distance metric
    var at = tileutil_world_to_tile(_ax, _ay);
    var bt = tileutil_world_to_tile(_bx, _by);
    return tileutil_dist_chebyshev(at.x, at.y, bt.x, bt.y) <= COMBAT_AGGRO_RANGE_TILES;
}

function combat_interrupt_for_hit(_unit) {
    // Cancel any in-progress attack windup so it cannot land
    if (variable_struct_exists(_unit, "swing_active")) _unit.swing_active = false;
    if (variable_struct_exists(_unit, "swing_t")) _unit.swing_t = 0;
    if (variable_struct_exists(_unit, "swing_target_id")) _unit.swing_target_id = -1;

    // If PLAYER was interrupted during ATTACK, reset to idle intent (do not auto-resume)
    if (variable_struct_exists(_unit, "act_target_id")) {
        if (_unit.act == ACT_ATTACK) {
            _unit.act_target_id = -1;
            if (variable_struct_exists(_unit, "attack_cmd")) _unit.attack_cmd = false;
            if (variable_struct_exists(_unit, "attack_hold")) _unit.attack_hold = false;
            // queued action remains (single-slot) and may run after recovery
        }
    }

    _unit.act = ACT_HIT_RECOVERY;
    _unit.hitrec_t = COMBAT_HIT_RECOVERY_S;
}

function combat_apply_damage_to_enemy(_d, _enemy, _dmg) {
    if (_enemy.act == ACT_DEAD || _enemy.state == ENEMY_STATE_DEAD) return;

    _enemy.hp = max(0, _enemy.hp - _dmg);

    if (_enemy.hp <= 0) {
        combat_enemy_die(_d, _enemy);
    }
}

function combat_apply_damage_to_player(_player, _dmg) {
    _player.hp = max(0, _player.hp - _dmg);
}

function combat_tick_timers_unit(_unit, _dt) {
    if (_unit.atk_cd_t > 0) _unit.atk_cd_t = max(0, _unit.atk_cd_t - _dt);
    if (_unit.hitrec_t > 0) _unit.hitrec_t = max(0, _unit.hitrec_t - _dt);

    if (_unit.act == ACT_HIT_RECOVERY && _unit.hitrec_t <= 0) {
        _unit.act = ACT_IDLE;
    }
}

function combat_act_to_text(_act) {
    switch (_act) {
        case ACT_IDLE: return "IDLE";
        case ACT_MOVE_TO: return "MOVE";
        case ACT_ATTACK: return "ATTACK";
        case ACT_HIT_RECOVERY: return "HIT";
        case ACT_DEAD: return "DEAD";
    }
    return "???";
}

function combat_world_to_screen(_app, _cam, _wx, _wy) {
    var proj = (_app.view.mode == "ortho")
        ? _app.renderer.ortho_project(_wx, _wy)
        : _app.renderer.iso_project(_wx, _wy);

    return {
        x: proj.x - _cam.x + _cam.vw * 0.5,
        y: proj.y - _cam.y + _cam.vh * 0.5
    };
}

// ------------------------------------------------------------
// Player order model:
// - single swing per click
// - continuous swings only while holding LMB on current target
// - repeated clicks while busy do NOT restart; they set a single-slot queued order
// ------------------------------------------------------------

function combat_player_try_pop_queued(_d) {
    var p = _d.player;

    if (!p.queued_attack_cmd) return;

    // If target is dead/missing, drop the queue
    var ei = combat_find_enemy_index_by_id(_d, p.queued_target_id);
    if (ei < 0) {
        p.queued_attack_cmd = false;
        p.queued_target_id = -1;
        return;
    }
    var e = _d.enemies[ei];
    if (e.hp <= 0 || e.act == ACT_DEAD || e.state == ENEMY_STATE_DEAD) {
        p.queued_attack_cmd = false;
        p.queued_target_id = -1;
        return;
    }

    // Pop
    p.act_target_id = p.queued_target_id;
    p.attack_cmd = true;
    p.queued_attack_cmd = false;
    p.queued_target_id = -1;
}

// Issue attack order (click on enemy)
function combat_player_issue_attack_order(_d, _enemy_id) {
    var p = _d.player;

    // If currently recovering or attacking, queue it (single-slot)
    if (p.act == ACT_ATTACK || p.act == ACT_HIT_RECOVERY) {
        p.queued_attack_cmd = true;
        p.queued_target_id = _enemy_id;
        return;
    }

    // Otherwise start immediately
    p.act_target_id = _enemy_id;
    p.attack_cmd = true;
}

// ------------------------------------------------------------
// Player step
// ------------------------------------------------------------
function combat_step_player(_d, _dt) {
    var p = _d.player;

    // tick timers
    combat_tick_timers_unit(p, _dt);

    // Allow queued order to pop only when fully idle
    if (p.act == ACT_IDLE && !p.swing_active) {
        combat_player_try_pop_queued(_d);
    }

    // If no target, idle combat state and return
    if (p.act_target_id < 0) {
        // If moving due to click-move, show MOVE state (else IDLE)
        if (_d.move_active) p.act = ACT_MOVE_TO;
        else p.act = ACT_IDLE;
        return;
    }

    // Validate target
    var ei = combat_find_enemy_index_by_id(_d, p.act_target_id);
    if (ei < 0) {
        p.act_target_id = -1;
        p.attack_cmd = false;
        p.attack_hold = false;
        return;
    }

    var e = _d.enemies[ei];
    if (e.hp <= 0 || e.act == ACT_DEAD || e.state == ENEMY_STATE_DEAD) {
        p.act_target_id = -1;
        p.attack_cmd = false;
        p.attack_hold = false;
        return;
    }

    // If in hit recovery, do nothing else
    if (p.act == ACT_HIT_RECOVERY) return;

    // If holding on target, keep trying as cooldown allows
    var wants_attack = p.attack_cmd || p.attack_hold;

    // Move into range if needed (simple direct move target already exists)
    var in_range = combat_in_melee_range(p.x, p.y, e.x, e.y);

    if (!in_range) {
        // chase target position
        p.act = ACT_MOVE_TO;
        _d.actions.set_move_target(e.x, e.y);
        return;
    }

    // In range
    if (!wants_attack) {
        p.act = ACT_IDLE;
        return;
    }

    // Cooldown gate
    if (p.atk_cd_t > 0) {
        p.act = ACT_ATTACK; // stays in ATTACK state while waiting (design choice)
        return;
    }

    // Start swing windup (if not already)
    if (!p.swing_active) {
        p.swing_active = true;
        p.swing_t = COMBAT_ATTACK_WINDUP_S;
        p.swing_target_id = p.act_target_id;

        // consume one-shot click request
        p.attack_cmd = false;

        p.act = ACT_ATTACK;
        return;
    }

    // Tick swing and resolve
    p.act = ACT_ATTACK;
    p.swing_t -= _dt;

    if (p.swing_t <= 0) {
        // Validate target again at hit frame
        var hit_i = combat_find_enemy_index_by_id(_d, p.swing_target_id);
        if (hit_i >= 0) {
            var hit_e = _d.enemies[hit_i];
            if (!(hit_e.hp <= 0 || hit_e.act == ACT_DEAD || hit_e.state == ENEMY_STATE_DEAD)) {
                if (combat_in_melee_range(p.x, p.y, hit_e.x, hit_e.y)) {
                    // Apply damage (enemy may die -> drops item)
                    // Compute damage (weapon slot bonus)
                    var dmg = COMBAT_DAMAGE_MELEE;
                    if (is_struct(_d.player) && is_struct(_d.player.equipment) && is_struct(_d.player.equipment.weapon)) {
                        var wn = "";
                        if (variable_struct_exists(_d.player.equipment.weapon, "name") && _d.player.equipment.weapon.name != undefined) {
                            wn = string_lower(string(_d.player.equipment.weapon.name));
                        }
                        // Minimal tuning: swords hit harder
                        if (string_pos("sword", wn) > 0) dmg += 2;
                    }

                    combat_apply_damage_to_enemy(_d, hit_e, dmg);

                    // Write-back enemy struct (since we modified local)
                    _d.enemies[hit_i] = hit_e;

                    // If enemy died, clear target immediately (optional)
                    if (hit_e.hp <= 0) {
                        p.act_target_id = -1;
                        p.attack_hold = false;
                        p.attack_cmd = false;
                    }
                }
            }
        }

        // End swing, set cooldown
        p.swing_active = false;
        p.swing_t = 0;
        p.swing_target_id = -1;

        p.atk_cd_t = COMBAT_ATTACK_COOLDOWN_S;
    }
}

// ------------------------------------------------------------
// Enemy step vs player (already present in your project)
// (This file previously contained it; keeping as-is below by reusing your existing code.)
// ------------------------------------------------------------

function combat_step_enemy_vs_player(_d, _e, _dt) {
    // Back-compat defaults
    if (_e.act == undefined) _e.act = ACT_IDLE;
    if (_e.act_target_kind == undefined) _e.act_target_kind = "none";
    if (_e.atk_cd_t == undefined) _e.atk_cd_t = 0;
    if (_e.hitrec_t == undefined) _e.hitrec_t = 0;
    if (_e.damage_melee == undefined) _e.damage_melee = COMBAT_DAMAGE_MELEE;
    if (_e.swing_active == undefined) _e.swing_active = false;
    if (_e.swing_t == undefined) _e.swing_t = 0;

    // Dead: no combat
    if (_e.hp <= 0 || _e.act == ACT_DEAD || _e.state == ENEMY_STATE_DEAD) {
        _e.hp = 0;
        _e.act = ACT_DEAD;
        _e.state = ENEMY_STATE_DEAD;
        _e.act_target_kind = "none";
        return;
    }

    // Tick timers
    combat_tick_timers_unit(_e, _dt);

    // Hit recovery: no actions
    if (_e.act == ACT_HIT_RECOVERY) return;

    // Acquire: only if in aggro range
    var in_aggro = combat_in_aggro_range(_e.x, _e.y, _d.player.x, _d.player.y);
    if (!in_aggro) {
        // Enemy AI controls chase/return; combat intent off
        if (_e.act == ACT_ATTACK) _e.act = ACT_IDLE;
        _e.act_target_kind = "none";
        _e.swing_active = false;
        _e.swing_t = 0;
        return;
    }

    _e.act_target_kind = "player";

    // Move into melee range (EnemyAi handles movement; combat just decides ATTACK label + timing)
    var in_range = combat_in_melee_range(_e.x, _e.y, _d.player.x, _d.player.y);

    if (!in_range) {
        // EnemyAi will move; label as MOVE
        _e.act = ACT_MOVE_TO;
        _e.swing_active = false;
        _e.swing_t = 0;
        return;
    }

    // In range: attempt attack
    _e.act = ACT_ATTACK;

    if (_e.atk_cd_t > 0) return;

    if (!_e.swing_active) {
        _e.swing_active = true;
        _e.swing_t = COMBAT_ATTACK_WINDUP_S;
        return;
    }

    _e.swing_t -= _dt;
    if (_e.swing_t <= 0) {
        // Apply damage to player + interrupt
        combat_apply_damage_to_player(_d.player, _e.damage_melee);
        combat_interrupt_for_hit(_d.player);

        _e.swing_active = false;
        _e.swing_t = 0;

        _e.atk_cd_t = COMBAT_ATTACK_COOLDOWN_S;
    }
}
