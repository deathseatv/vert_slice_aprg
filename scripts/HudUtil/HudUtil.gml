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
// ================================
// Inventory UI Controller (Phase 3)
// - Keeps inventory UI interaction and rendering in one place.
// - Exposes two entry points: step(app, cam, mouse) and draw(app)
// ================================

function invui_get_controller() {
    // Singleton controller stored on global to avoid per-frame allocations.
    if (!variable_global_exists("_invui_controller") || !is_struct(global._invui_controller)) {
        global._invui_controller = {
            /// step(app, cam, mouse) -> { ui_consumed: bool, intent: optional struct }
            /// mouse: { sx, sy } in GUI coordinates
            step: function(_app, _cam, _mouse) {
                var out = { ui_consumed: false, intent: undefined };

                if (!_app.domain.inventory_open) {
                    // Ensure UI transient states aren't stuck between opens
                    _app.domain.inv_drag_active = false;
                    _app.domain.inv_drag_moved = false;
                    return out;
                }

                var gw = display_get_gui_width();
                var gh = display_get_gui_height();

                // Panel geometry
                var panel_w = gw * 0.5;
                var col_w = 56;
                var col_x1 = panel_w - col_w;
                var col_x2 = panel_w;
                var col_y1 = 0;
                var col_y2 = gh;

                // Equip slot (to the left of icon column)
                var equip_size = 40;
                var equip_pad = 12;
                var equip_x2 = col_x1 - equip_pad;
                var equip_x1 = equip_x2 - equip_size;
                var equip_y1 = 16;
                var equip_y2 = equip_y1 + equip_size;

                var msx = _mouse.sx;
                var msy = _mouse.sy;

                var mouse_in_panel = (msx >= 0 && msx < panel_w);
                var mouse_in_column = (msx >= col_x1 && msx < col_x2 && msy >= col_y1 && msy < col_y2);
                var mouse_in_world_area = (msx >= panel_w);

                // Inventory content sizing (for scroll bounds)
                var ICON = 32;
                var SPACING = 8;
                var PAD_TOP = 16;
                var PAD_BOT = 16;
                var pitch = ICON + SPACING;

                var inv = _app.domain.player.inventory;
                var inv_count = is_array(inv) ? array_length(inv) : 0;

                var content_h = PAD_TOP + PAD_BOT;
                if (inv_count > 0) content_h += inv_count * ICON + max(0, inv_count - 1) * SPACING;

                var max_scroll = max(0, content_h - gh);
                _app.domain.inv_scroll_offset_px = clamp(_app.domain.inv_scroll_offset_px, 0, max_scroll);

                // ----------------------------
                // Carry interactions (highest priority while active)
                // ----------------------------
                if (_app.domain.carry_active) {
                    // Right-click anywhere => return (consumes input)
                    if (_app.input.mouse_pressed_right()) {
                        var idx_back = _app.domain.carry_original_index;
                        if (idx_back == undefined || idx_back < 0) idx_back = array_length(_app.domain.player.inventory);
                        idx_back = clamp(idx_back, 0, array_length(_app.domain.player.inventory));
                        array_insert(_app.domain.player.inventory, idx_back, _app.domain.carry_item);

                        _app.domain.carry_active = false;
                        _app.domain.carry_item = undefined;
                        _app.domain.carry_original_index = -1;

                        out.ui_consumed = true;
                    }
                    // Left-click on equip slot => equip (consumes input)
                    else if (_app.input.mouse_pressed_left() && msx >= equip_x1 && msx <= equip_x2 && msy >= equip_y1 && msy <= equip_y2) {
                        _app.domain.player.equipment.weapon = _app.domain.carry_item;

                        _app.domain.carry_active = false;
                        _app.domain.carry_item = undefined;
                        _app.domain.carry_original_index = -1;

                        out.ui_consumed = true;
                    }
                    // Left-click in world area (outside panel) => drop (consumes input)
                    else if (_app.input.mouse_pressed_left() && mouse_in_world_area) {
                        var nm = "item";
                        if (is_struct(_app.domain.carry_item) && _app.domain.carry_item.name != undefined) nm = _app.domain.carry_item.name;

                        // Output intent; obj_game performs simulation action.
                        // Include GUI mouse coords so the simulation can deterministically
                        // translate cursor -> world -> tile center.
                        out.intent = { type: "inv_drop_item_at_cursor_named", name: nm, sx: msx, sy: msy };

                        _app.domain.carry_active = false;
                        _app.domain.carry_item = undefined;
                        _app.domain.carry_original_index = -1;

                        out.ui_consumed = true;
                    }
                    else {
                        // Carry active: suppress world clicks that happen inside the panel.
                        if (_app.input.mouse_pressed_left() && mouse_in_panel) out.ui_consumed = true;
                    }

                    // Carry active => never hold-attack
                    _app.domain.player.attack_hold = false;
                }
                // ----------------------------
                // Equip slot interactions when not carrying
                // ----------------------------
                else if (_app.input.mouse_pressed_left() && msx >= equip_x1 && msx <= equip_x2 && msy >= equip_y1 && msy <= equip_y2) {
                    // Unequip to inventory (end)
                    if (is_struct(_app.domain.player.equipment.weapon)) {
                        array_push(_app.domain.player.inventory, _app.domain.player.equipment.weapon);
                        _app.domain.player.equipment.weapon = undefined;
                    }
                    out.ui_consumed = true;
                }
                // ----------------------------
                // Column interactions (scroll + click-to-pick) when not carrying
                // ----------------------------
                else if (mouse_in_column) {
                    // Begin drag on press
                    if (_app.input.mouse_pressed_left()) {
                        _app.domain.inv_drag_active = true;
                        _app.domain.inv_drag_moved = false;
                        _app.domain.inv_drag_start_mouse_y = msy;
                        _app.domain.inv_drag_start_scroll_offset = _app.domain.inv_scroll_offset_px;
                        out.ui_consumed = true;
                    }

                    // Update drag while held
                    if (_app.domain.inv_drag_active && _app.input.mouse_down_left()) {
                        var dy = msy - _app.domain.inv_drag_start_mouse_y;
                        if (abs(dy) > 3) _app.domain.inv_drag_moved = true;

                        var new_off = _app.domain.inv_drag_start_scroll_offset - dy;
                        _app.domain.inv_scroll_offset_px = clamp(new_off, 0, max_scroll);

                        out.ui_consumed = true;
                    }

                    // End gesture on release: treat as click if we didn't move meaningfully
                    if (_app.domain.inv_drag_active && !_app.input.mouse_down_left()) {
                        var was_drag = _app.domain.inv_drag_moved;

                        _app.domain.inv_drag_active = false;
                        _app.domain.inv_drag_moved = false;

                        if (!was_drag) {
                            // Hit-test icon at current mouse, using scroll offset
                            if (is_array(inv) && array_length(inv) > 0) {
                                var local_y = msy + _app.domain.inv_scroll_offset_px - PAD_TOP;
                                var idx = floor(local_y / pitch);

                                if (idx >= 0 && idx < array_length(inv)) {
                                    var icon_top = PAD_TOP + idx * pitch - _app.domain.inv_scroll_offset_px;
                                    var icon_bot = icon_top + ICON;

                                    // Only clickable if within visible column bounds
                                    if (icon_bot >= 0 && icon_top <= gh) {
                                        // Pick up: remove from inventory immediately to prevent duplicates
                                        var picked = inv[idx];
                                        array_delete(inv, idx, 1);

                                        if (picked == undefined) picked = { name: "???" };
                                        if (!is_struct(picked)) picked = { name: string(picked) };

                                        _app.domain.carry_active = true;
                                        _app.domain.carry_item = picked;
                                        _app.domain.carry_original_index = idx;

                                        // Clamp scroll after removal
                                        inv_count = array_length(inv);
                                        content_h = PAD_TOP + PAD_BOT;
                                        if (inv_count > 0) content_h += inv_count * ICON + max(0, inv_count - 1) * SPACING;
                                        max_scroll = max(0, content_h - gh);
                                        _app.domain.inv_scroll_offset_px = clamp(_app.domain.inv_scroll_offset_px, 0, max_scroll);
                                    }
                                }
                            }

                            out.ui_consumed = true;
                        }
                    }
                } else {
                    // Click started outside column => cancel any drag state
                    if (_app.input.mouse_pressed_left()) {
                        _app.domain.inv_drag_active = false;
                        _app.domain.inv_drag_moved = false;
                    }
                }

                // Block gameplay clicks that occur on the covered panel area.
                if (mouse_in_panel && (_app.input.mouse_pressed_left() || _app.input.mouse_down_left())) {
                    out.ui_consumed = true;
                }

                return out;
            },

            /// draw(app)
            draw: function(_app) {
                if (!_app.domain.inventory_open) return;

                var gw = display_get_gui_width();
                var gh = display_get_gui_height();

                var panel_w = gw * 0.5;

                // Panel background
                draw_set_alpha(1);
                draw_set_color(c_dkgray);
                draw_rectangle(0, 0, panel_w, gh, false);
                draw_set_alpha(1);

                // Header
                draw_set_color(c_white);
                draw_text(16, 80, "INVENTORY");

                // Equip slot (left of icon column)
                var col_x1 = panel_w - 56;

                var equip_size = 40;
                var equip_pad = 12;
                var equip_x2 = col_x1 - equip_pad;
                var equip_x1 = equip_x2 - equip_size;
                var equip_y1 = 16;
                var equip_y2 = equip_y1 + equip_size;

                draw_set_alpha(1);
                draw_set_color(c_black);
                draw_rectangle(equip_x1 - 2, equip_y1 - 2, equip_x2 + 2, equip_y2 + 2, false);
                draw_set_alpha(0.9);
                draw_set_color(c_ltgray);
                draw_rectangle(equip_x1, equip_y1, equip_x2, equip_y2, false);
                draw_set_alpha(1);

                draw_set_color(c_white);
                draw_text(equip_x1, equip_y2 + 6, "EQUIPPED");

                // Equipped item label
                if (is_struct(_app.domain.player.equipment.weapon)) {
                    var w = _app.domain.player.equipment.weapon;
                    var nmw = "item";
                    if (variable_struct_exists(w, "name") && w.name != undefined) nmw = string(w.name);
                    // simple icon letter
                    var ch = string_upper(string_copy(nmw, 1, 1));
                    draw_set_color(c_dkgray);
                    draw_rectangle(equip_x1 + 4, equip_y1 + 4, equip_x2 - 4, equip_y2 - 4, false);
                    draw_set_color(c_white);
                    draw_text(equip_x1 + 14, equip_y1 + 10, ch);
                    draw_text(equip_x1, equip_y2 + 22, nmw);
                } else {
                    draw_set_color(c_white);
                    draw_text(equip_x1, equip_y2 + 22, "(none)");
                }

                // Text list (left area)
                var inv = _app.domain.player.inventory;
                var inv_y = 104;

                if (!is_array(inv) || array_length(inv) <= 0) {
                    draw_text(16, inv_y, "(empty)");
                } else {
                    for (var ii = 0; ii < array_length(inv); ii++) {
                        var row = inv[ii];
                        var name = (is_struct(row) && row.name != undefined) ? row.name : "???";
                        draw_text(16, inv_y, "- " + string(name));
                        inv_y += 16;
                    }
                }

                // Icon column widget (right 56px of panel)
                var col_w = 56;
                var col_x1 = panel_w - col_w;
                var col_x2 = panel_w;

                draw_set_alpha(0.9);
                draw_set_color(c_gray);
                draw_rectangle(col_x1, 0, col_x2, gh, false);
                draw_set_alpha(1);

                var ICON = 32;
                var PAD_TOP = 16;
                var SPACING = 8;
                var pitch = ICON + SPACING;

                var scroll = _app.domain.inv_scroll_offset_px;

                if (is_array(inv)) {
                    var n = array_length(inv);
                    var icon_x = col_x1 + floor((col_w - ICON) * 0.5);

                        var equipped_uid = -1;
                        var equipped_name = "";
                        if (is_struct(_app.domain.player) && is_struct(_app.domain.player.equipment) && is_struct(_app.domain.player.equipment.weapon)) {
                            var w = _app.domain.player.equipment.weapon;
                            if (variable_struct_exists(w, "uid") && w.uid != undefined) equipped_uid = w.uid;
                            if (variable_struct_exists(w, "name") && w.name != undefined) equipped_name = string_lower(string(w.name));
                        }


                    for (var i = 0; i < n; i++) {
                        var _y = PAD_TOP + i * pitch - scroll;
                        var y2 = _y + ICON;

                        if (y2 < 0 || _y > gh) continue;

                        // Icon container
                        draw_set_alpha(0.85);
                        draw_set_color(c_black);

                        // Highlight equipped weapon
                        var row = inv[i];
                        var row_uid = -1;
                        var row_name = "";
                        if (is_struct(row)) {
                            if (variable_struct_exists(row, "uid") && row.uid != undefined) row_uid = row.uid;
                            if (variable_struct_exists(row, "name") && row.name != undefined) row_name = string_lower(string(row.name));
                        }
                        var is_equipped = false;
                        if (equipped_uid >= 0 && row_uid >= 0) is_equipped = (row_uid == equipped_uid);
                        else if (equipped_name != "") is_equipped = (row_name == equipped_name);

                        if (is_equipped) draw_set_color(c_dkgray);
                        draw_rectangle(icon_x, _y, icon_x + ICON, _y + ICON, false);
                        draw_set_alpha(1);
                        draw_set_color(c_white);
                        draw_rectangle(icon_x, _y, icon_x + ICON, _y + ICON, true);

                        // Letter glyph
                        var nm = " ?";
                        if (is_struct(inv[i]) && inv[i].name != undefined) nm = string(inv[i].name);
                        else if (inv[i] != undefined) nm = string(inv[i]);

                        var ch = string_char_at(nm, 1);
                        draw_set_color(c_white);
                        draw_text(icon_x + 10, _y + 8, string_upper(ch));
                    }
                }

                // Carry icon at cursor
                if (_app.domain.carry_active) {
                    var cx = device_mouse_x_to_gui(0);
                    var cy = device_mouse_y_to_gui(0);

                    draw_set_alpha(0.9);
                    draw_set_color(c_black);
                    draw_rectangle(cx - 16, cy - 16, cx + 16, cy + 16, false);
                    draw_set_alpha(1);

                    draw_set_color(c_white);
                    draw_rectangle(cx - 16, cy - 16, cx + 16, cy + 16, true);

                    var cnm = " ?";
                    if (is_struct(_app.domain.carry_item) && _app.domain.carry_item.name != undefined) cnm = string(_app.domain.carry_item.name);
                    var cch = string_char_at(cnm, 1);

                    draw_set_color(c_white);
                    draw_text(cx + 10, cy + 8, string_upper(cch));
                }
            }
        };
    }

    return global._invui_controller;
}
