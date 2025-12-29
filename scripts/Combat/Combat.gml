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

function combat_enemy_die(_e) {
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

function combat_apply_damage_to_enemy(_enemy, _dmg) {
    if (_enemy.act == ACT_DEAD || _enemy.state == ENEMY_STATE_DEAD) return;

    _enemy.hp = max(0, _enemy.hp - _dmg);

    if (_enemy.hp <= 0) {
        combat_enemy_die(_enemy);
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
    if (!p.queued_attack_cmd) return false;

    var ei = combat_find_enemy_index_by_id(_d, p.queued_target_id);
    if (ei < 0) {
        p.queued_attack_cmd = false;
        p.queued_target_id = -1;
        return false;
    }

    var e = _d.enemies[ei];
    if (e.hp <= 0 || e.act == ACT_DEAD || e.state == ENEMY_STATE_DEAD) {
        p.queued_attack_cmd = false;
        p.queued_target_id = -1;
        return false;
    }

    p.act_target_id = p.queued_target_id;
    p.attack_cmd = true;

    p.queued_attack_cmd = false;
    p.queued_target_id = -1;
    return true;
}

function combat_player_issue_attack_order(_d, _enemy_id) {
    var p = _d.player;

    // ignore dead/invalid target
    var ei = combat_find_enemy_index_by_id(_d, _enemy_id);
    if (ei < 0) return;

    var e = _d.enemies[ei];
    if (e.hp <= 0 || e.act == ACT_DEAD || e.state == ENEMY_STATE_DEAD) return;

    // busy => queue (single slot), do not restart/interrupt current action
    var busy = (p.act_target_id >= 0) || p.swing_active || (p.act == ACT_HIT_RECOVERY);

    if (!busy) {
        p.act_target_id = _enemy_id;
        p.attack_cmd = true; // one-shot unless held
    } else {
        p.queued_attack_cmd = true;
        p.queued_target_id = _enemy_id; // overwrite single slot
    }
}

function combat_step_player(_d, _dt) {
    var p = _d.player;

    // timers + hit recovery
    combat_tick_timers_unit(p, _dt);
    if (p.act == ACT_HIT_RECOVERY) return;

    // no current target: run queued next-action if any
    if (p.act_target_id < 0) {
        if (!combat_player_try_pop_queued(_d)) {
            p.attack_cmd = false;
            p.attack_hold = false;
            p.swing_active = false;
            p.swing_t = 0;
            p.swing_target_id = -1;
            p.act = (_d.move_active) ? ACT_MOVE_TO : ACT_IDLE;
            return;
        }
        // fall through with new act_target_id
    }

    var ei = combat_find_enemy_index_by_id(_d, p.act_target_id);
    if (ei < 0) {
        p.act_target_id = -1;
        p.attack_cmd = false;
        p.attack_hold = false;
        p.swing_active = false;
        p.swing_t = 0;
        p.swing_target_id = -1;

        combat_player_try_pop_queued(_d);

        p.act = (_d.move_active) ? ACT_MOVE_TO : ACT_IDLE;
        return;
    }

    var e = _d.enemies[ei];

    // dead target: clear and attempt queued
    if (e.hp <= 0 || e.act == ACT_DEAD || e.state == ENEMY_STATE_DEAD) {
        p.act_target_id = -1;
        p.attack_cmd = false;
        p.attack_hold = false;
        p.swing_active = false;
        p.swing_t = 0;
        p.swing_target_id = -1;

        combat_player_try_pop_queued(_d);

        p.act = (_d.move_active) ? ACT_MOVE_TO : ACT_IDLE;
        return;
    }

    var wants_attack = (p.attack_hold || p.attack_cmd);

    // If swing is pending but target moved out of melee, cancel swing
    if (p.swing_active && !combat_in_melee_range(p.x, p.y, e.x, e.y)) {
        p.swing_active = false;
        p.swing_t = 0;
        p.swing_target_id = -1;

        // if this was a one-shot click (not hold), cancel intent entirely
        if (!p.attack_hold) {
            p.act_target_id = -1;
            p.attack_cmd = false;
            p.act = ACT_IDLE;

            combat_player_try_pop_queued(_d);
            return;
        }
    }

    // In melee range
    if (combat_in_melee_range(p.x, p.y, e.x, e.y)) {
        // hard stop so we don't drift while attacking/windup
        _d.move_queue = [];
        _d.move_active = false;

        // no intent and no active swing => idle
        if (!wants_attack && !p.swing_active) {
            p.act = ACT_IDLE;
            return;
        }

        // start swing windup if possible
        if (!p.swing_active && p.atk_cd_t <= 0 && wants_attack) {
            p.swing_active = true;
            p.swing_t = COMBAT_ATTACK_WINDUP_S;
            p.swing_target_id = p.act_target_id;
            p.act = ACT_ATTACK;

            // consume one-shot command immediately so an interrupt cancels the attempt
            if (!p.attack_hold) p.attack_cmd = false;
        }

        // windup / resolve
        if (p.swing_active) {
            p.act = ACT_ATTACK;
            p.swing_t = max(0, p.swing_t - _dt);

            if (p.swing_t <= 0) {
                // re-find at moment of hit
                var hi = combat_find_enemy_index_by_id(_d, p.swing_target_id);
                if (hi >= 0) {
                    var he = _d.enemies[hi];

                    // if still valid + in melee at the moment, land hit
                    if (he.hp > 0 && he.act != ACT_DEAD && he.state != ENEMY_STATE_DEAD
                        && combat_in_melee_range(p.x, p.y, he.x, he.y)) {
                        combat_apply_damage_to_enemy(he, COMBAT_DAMAGE_MELEE);
                        if (he.act != ACT_DEAD) combat_interrupt_for_hit(he);
                        p.atk_cd_t = COMBAT_ATTACK_COOLDOWN_S;
                    }
                }

                // swing completes (hit or whiff)
                p.swing_active = false;
                p.swing_t = 0;
                p.swing_target_id = -1;

                // single-swing behavior unless holding
                if (!p.attack_hold) {
                    p.act_target_id = -1;
                    p.act = ACT_IDLE;

                    // run queued next-action (single slot)
                    combat_player_try_pop_queued(_d);
                }
            }
        } else {
            // holding in melee but waiting on cooldown
            p.act = (p.attack_hold) ? ACT_ATTACK : ACT_IDLE;
        }

        return;
    }

    // Not in melee range: only chase if outstanding intent exists
    if (!wants_attack) {
        p.act_target_id = -1;
        p.act = (_d.move_active) ? ACT_MOVE_TO : ACT_IDLE;

        combat_player_try_pop_queued(_d);
        return;
    }

    p.act = ACT_MOVE_TO;
    _d.actions.set_move_target(e.x, e.y);
}

function combat_step_enemy_vs_player(_d, _e, _dt) {
    // dead enemies do nothing
    if (_e.hp <= 0 || _e.act == ACT_DEAD || _e.state == ENEMY_STATE_DEAD) {
        _e.hp = 0;
        _e.act = ACT_DEAD;
        _e.state = ENEMY_STATE_DEAD;
        _e.act_target_kind = "none";
        _e.swing_active = false;
        _e.swing_t = 0;
        return;
    }

    // timers + hit recovery
    combat_tick_timers_unit(_e, _dt);
    if (_e.act == ACT_HIT_RECOVERY) return;

    var p = _d.player;

    // not aggro: do not override base AI
    if (!combat_in_aggro_range(_e.x, _e.y, p.x, p.y)) {
        _e.act_target_kind = "none";
        _e.swing_active = false;
        _e.swing_t = 0;
        return;
    }

    _e.act_target_kind = "player";

    // ensure chase uses existing pathing
    if (_e.state != ENEMY_STATE_CHASE) {
        enemyai_set_state(_e, ENEMY_STATE_CHASE);
    }

    // cancel windup if target moved out of melee
    if (_e.swing_active && !combat_in_melee_range(_e.x, _e.y, p.x, p.y)) {
        _e.swing_active = false;
        _e.swing_t = 0;
    }

    // melee: windup then hit
    if (combat_in_melee_range(_e.x, _e.y, p.x, p.y)) {
        _e.act = ACT_ATTACK;

        if (!_e.swing_active && _e.atk_cd_t <= 0) {
            _e.swing_active = true;
            _e.swing_t = COMBAT_ATTACK_WINDUP_S;
        }

        if (_e.swing_active) {
            _e.swing_t = max(0, _e.swing_t - _dt);

            if (_e.swing_t <= 0) {
                // if still in melee, land hit; otherwise whiff
                if (combat_in_melee_range(_e.x, _e.y, p.x, p.y)) {
                    combat_apply_damage_to_player(p, _e.damage_melee);
                    combat_interrupt_for_hit(p);
                    _e.atk_cd_t = COMBAT_ATTACK_COOLDOWN_S;
                }

                _e.swing_active = false;
                _e.swing_t = 0;
            }
        }

        return;
    }

    // otherwise chase (movement handled by EnemyAi)
    _e.act = ACT_MOVE_TO;
}
