// ================================
// FILE: scripts/HudUtil/HudUtil.gml
// REPLACE ENTIRE FILE WITH THIS
// ================================
// scripts/HudUtil/HudUtil.gml
/// HUD utilities
/// - Hover resolution (enemy under cursor, tile-based)
/// - Hover resolution (item under cursor, tile-based)
/// - Minimal HP bar rendering for Draw GUI

function hud_get_hovered_enemy_from_world(_app, _wx, _wy) {
    // mouse world -> mouse tile
    var mt = tileutil_world_to_tile(_wx, _wy);
    var mtx = mt.x;
    var mty = mt.y;

    // Find best enemy on that tile (nearest to mouse world pos)
    var best_i = -1;
    var best_d = 999999999;

    var n = array_length(_app.domain.enemies);
    for (var i = 0; i < n; i++) {
        var e = _app.domain.enemies[i];

        // dead targets are not hoverable / highlightable
        if (e.hp <= 0 || e.act == ACT_DEAD || e.state == ENEMY_STATE_DEAD) continue;

        var et = tileutil_world_to_tile(e.x, e.y);

        if (et.x == mtx && et.y == mty) {
            var d = point_distance(e.x, e.y, _wx, _wy);
            if (d < best_d) {
                best_d = d;
                best_i = i;
            }
        }
    }

    if (best_i < 0) return undefined;
    return _app.domain.enemies[best_i];
}

function hud_get_hovered_enemy(_app, _cam) {
    var msx = device_mouse_x_to_gui(0);
    var msy = device_mouse_y_to_gui(0);

    var w;
    if (_app.view.mode == "ortho") w = _app.proj.screen_to_world_ortho(msx, msy, _cam);
    else w = _app.proj.screen_to_world_iso(msx, msy, _cam);

    return hud_get_hovered_enemy_from_world(_app, w.x, w.y);
}

// ----------------------------
// Items
// ----------------------------
function hud_get_hovered_item_from_world(_app, _wx, _wy) {
    if (!is_array(_app.domain.items)) return undefined;

    // mouse tile
    var mt = tileutil_world_to_tile(_wx, _wy);
    var mtx = mt.x;
    var mty = mt.y;

    // Best item on that tile (nearest to cursor)
    var best_i = -1;
    var best_d = 999999999;

    var n = array_length(_app.domain.items);
    for (var i = 0; i < n; i++) {
        var it = _app.domain.items[i];
        if (it == undefined) continue;
        if (it.picked) continue;

        var tt = tileutil_world_to_tile(it.x, it.y);
        if (tt.x == mtx && tt.y == mty) {
            var d = point_distance(it.x, it.y, _wx, _wy);
            if (d < best_d) {
                best_d = d;
                best_i = i;
            }
        }
    }

    if (best_i < 0) return undefined;
    return _app.domain.items[best_i];
}

function hud_get_hovered_item(_app, _cam) {
    var msx = device_mouse_x_to_gui(0);
    var msy = device_mouse_y_to_gui(0);

    var w;
    if (_app.view.mode == "ortho") w = _app.proj.screen_to_world_ortho(msx, msy, _cam);
    else w = _app.proj.screen_to_world_iso(msx, msy, _cam);

    return hud_get_hovered_item_from_world(_app, w.x, w.y);
}

// ----------------------------
// UI widgets
// ----------------------------
function hud_draw_hp_bar(_x, _y, _w, _h, _hp, _hp_max, _label) {
    var _frac = 0;
    if (_hp_max > 0) _frac = clamp(_hp / _hp_max, 0, 1);

    // Label
    draw_set_color(c_white);
    draw_text(_x, _y - 14, _label + " HP: " + string(_hp) + " / " + string(_hp_max));

    // Background (filled)
    draw_set_color(c_black);
    draw_rectangle(_x, _y, _x + _w, _y + _h, false);

    // Fill (filled)
    var fill_w = (_w - 2) * _frac;
    draw_set_color(c_lime);
    draw_rectangle(_x + 1, _y + 1, _x + 1 + fill_w, _y + _h - 1, false);

    // Outline
    draw_set_color(c_white);
    draw_rectangle(_x, _y, _x + _w, _y + _h, true);
}
