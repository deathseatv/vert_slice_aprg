// ================================
// FILE: objects/obj_game/Step_0.gml
// REPLACE ENTIRE FILE WITH THIS
// ================================
// objects/obj_game/Step_0.gml
var app = global.app;

// Toggle console (always allowed)
if (app.input.pressed("toggle_console")) {
    app.cmd.dispatch({ type: "cmd_toggle_console" });
}

// If console is open, it captures input and gameplay inputs must not fire
if (app.console.open) {
    // close on escape
    if (keyboard_check_pressed(vk_escape)) {
        app.cmd.dispatch({ type: "cmd_close_console" });
    }

    // ensure we don't "stick" attack hold while console is open
    app.domain.player.attack_hold = false;

    // update console input line
    app.console.step();

    // submit on enter
    if (keyboard_check_pressed(vk_enter)) {
        app.cmd.dispatch({ type: "cmd_console_submit", line: app.console.input_line });
        keyboard_string = "";
        app.console.input_line = "";
    }

    // BRIDGE: consume pending_spawn right here (guaranteed to run)
    if (is_struct(app.console.pending_spawn)) {
        var req = app.console.pending_spawn;
        app.console.pending_spawn = undefined;

        app.cmd.dispatch({ type: "cmd_spawn_enemy", tx: req.tx, ty: req.ty });
        app.console.print("Bridged spawn enemy " + string(req.tx) + " " + string(req.ty));
        app.diag.log("Bridged spawn enemy " + string(req.tx) + " " + string(req.ty));
    }


    // BRIDGE: consume pending_give right here (guaranteed to run)
    if (is_struct(app.console.pending_give)) {
        var reqg = app.console.pending_give;
        app.console.pending_give = undefined;

        app.cmd.dispatch({ type: "cmd_give_item", target: reqg.target, item: reqg.item, count: reqg.count });
        app.console.print("Bridged give " + string(reqg.target) + " " + string(reqg.item) + " " + string(reqg.count));
        app.diag.log("Bridged give " + string(reqg.target) + " " + string(reqg.item) + " " + string(reqg.count));
    }


    // BRIDGE: consume pending_give right here (guaranteed to run)
    if (is_struct(app.console.pending_give)) {
        var reqg = app.console.pending_give;
        app.console.pending_give = undefined;

        app.cmd.dispatch({ type: "cmd_give_item", target: reqg.target, item: reqg.item, count: reqg.count });
        app.console.print("Bridged give " + string(reqg.target) + " " + string(reqg.item) + " " + string(reqg.count));
        app.diag.log("Bridged give " + string(reqg.target) + " " + string(reqg.item) + " " + string(reqg.count));
    }

    // simulation continues
    app.ports.action.impl.step_simulation(1 / room_speed);
    app.domain.build_render_packets();
} else {
    // ----------------------------
    // Inventory toggle (I) + close (Esc)
    // ----------------------------
    if (app.input.pressed("toggle_inventory")) {
        var was_open = app.domain.inventory_open;
        app.domain.inventory_open = !app.domain.inventory_open;

        // If closing inventory while carrying, always return item to avoid loss.
        if (was_open && !app.domain.inventory_open) {
            if (app.domain.carry_active) {
                var idx_ret = app.domain.carry_original_index;
                if (idx_ret == undefined || idx_ret < 0) idx_ret = array_length(app.domain.player.inventory);
                idx_ret = clamp(idx_ret, 0, array_length(app.domain.player.inventory));
                array_insert(app.domain.player.inventory, idx_ret, app.domain.carry_item);

                app.domain.carry_active = false;
                app.domain.carry_item = undefined;
                app.domain.carry_original_index = -1;
            }

            // reset scroll on close (spec choice)
            app.domain.inv_scroll_offset_px = 0;
            app.domain.inv_drag_active = false;
            app.domain.inv_drag_moved = false;
        }
    }
    if (app.domain.inventory_open && keyboard_check_pressed(vk_escape)) {
        // Treat Esc as close; same safety behavior as toggle close.
        if (app.domain.carry_active) {
            var idx_ret2 = app.domain.carry_original_index;
            if (idx_ret2 == undefined || idx_ret2 < 0) idx_ret2 = array_length(app.domain.player.inventory);
            idx_ret2 = clamp(idx_ret2, 0, array_length(app.domain.player.inventory));
            array_insert(app.domain.player.inventory, idx_ret2, app.domain.carry_item);

            app.domain.carry_active = false;
            app.domain.carry_item = undefined;
            app.domain.carry_original_index = -1;
        }

        app.domain.inventory_open = false;
        app.domain.inv_scroll_offset_px = 0;
        app.domain.inv_drag_active = false;
        app.domain.inv_drag_moved = false;
    }

    // normal gameplay input
    if (app.input.pressed("toggle_view")) {
        app.cmd.dispatch({ type: "cmd_toggle_view" });
    }

    // ----------------------------
    // Inventory UI input routing (when open)
    // ----------------------------
    var ui_consumed = false;

    if (app.domain.inventory_open) {
        var gw = display_get_gui_width();
        var gh = display_get_gui_height();

        var panel_w = gw * 0.5;
        var col_w = 56;
        var col_x1 = panel_w - col_w;
        var col_x2 = panel_w;
        var col_y1 = 0;
        var col_y2 = gh;

        var msx = device_mouse_x_to_gui(0);
        var msy = device_mouse_y_to_gui(0);

        var mouse_in_panel = (msx >= 0 && msx < panel_w);
        var mouse_in_column = (msx >= col_x1 && msx < col_x2 && msy >= col_y1 && msy < col_y2);
        var mouse_in_world_area = (msx >= panel_w);

        // Column layout constants (must match draw)
        var ICON = 32;
        var PAD_TOP = 12;
        var PAD_BOT = 12;
        var SPACING = 8;
        var pitch = ICON + SPACING;

        var inv = app.domain.player.inventory;
        var inv_count = is_array(inv) ? array_length(inv) : 0;

        var content_h = PAD_TOP + PAD_BOT;
        if (inv_count > 0) content_h += inv_count * ICON + max(0, inv_count - 1) * SPACING;

        var max_scroll = max(0, content_h - gh);
        app.domain.inv_scroll_offset_px = clamp(app.domain.inv_scroll_offset_px, 0, max_scroll);

        // ----------------------------
        // Carry interactions (highest priority while active)
        // ----------------------------
        if (app.domain.carry_active) {
            // Right-click anywhere => return (consumes input)
            if (app.input.mouse_pressed_right()) {
                var idx_back = app.domain.carry_original_index;
                if (idx_back == undefined || idx_back < 0) idx_back = array_length(app.domain.player.inventory);
                idx_back = clamp(idx_back, 0, array_length(app.domain.player.inventory));
                array_insert(app.domain.player.inventory, idx_back, app.domain.carry_item);

                app.domain.carry_active = false;
                app.domain.carry_item = undefined;
                app.domain.carry_original_index = -1;

                ui_consumed = true;
            }
            // Left-click in world area (outside panel) => drop (consumes input)
            else if (app.input.mouse_pressed_left() && mouse_in_world_area) {
                var nm = "item";
                if (is_struct(app.domain.carry_item) && app.domain.carry_item.name != undefined) nm = app.domain.carry_item.name;

                // Drop location is player-centric: nearest free tile to player (not cursor).
                app.ports.action.impl.spawn_item_drop_near_player_named(nm);

                app.domain.carry_active = false;
                app.domain.carry_item = undefined;
                app.domain.carry_original_index = -1;

                ui_consumed = true;
            }
            else {
                // Carry active: suppress world clicks that happen inside the panel.
                if (app.input.mouse_pressed_left() && mouse_in_panel) ui_consumed = true;
            }

            // Carry active => never hold-attack
            app.domain.player.attack_hold = false;
        }
        // ----------------------------
        // Column interactions (scroll + click-to-pick) when not carrying
        // ----------------------------
        else if (mouse_in_column) {
            // Begin gesture inside column captures input immediately
            if (app.input.mouse_pressed_left()) {
                app.domain.inv_drag_active = true;
                app.domain.inv_drag_start_mouse_y = msy;
                app.domain.inv_drag_start_scroll_offset = app.domain.inv_scroll_offset_px;
                app.domain.inv_drag_moved = false;
                ui_consumed = true;
            }

            // Update gesture while held
            if (app.domain.inv_drag_active && app.input.mouse_down_left()) {
                var dy = msy - app.domain.inv_drag_start_mouse_y;
                if (abs(dy) >= app.domain.inv_drag_threshold_px) app.domain.inv_drag_moved = true;

                var new_off = app.domain.inv_drag_start_scroll_offset - dy;
                app.domain.inv_scroll_offset_px = clamp(new_off, 0, max_scroll);

                ui_consumed = true;
            }

            // End gesture on release: treat as click if we didn't move meaningfully
            if (app.domain.inv_drag_active && !app.input.mouse_down_left()) {
                var was_drag = app.domain.inv_drag_moved;

                app.domain.inv_drag_active = false;
                app.domain.inv_drag_moved = false;

                if (!was_drag) {
                    // Hit-test icon at current mouse, using scroll offset
                    var local_y = msy + app.domain.inv_scroll_offset_px - PAD_TOP;
                    var idx = floor(local_y / pitch);

                    if (idx >= 0 && idx < inv_count) {
                        var icon_top = PAD_TOP + idx * pitch - app.domain.inv_scroll_offset_px;
                        var icon_bot = icon_top + ICON;

                        // Only clickable if within visible column bounds
                        if (icon_bot >= 0 && icon_top <= gh) {
                            // Pick up: remove from inventory immediately to prevent duplicates
                            var picked = inv[idx];
                            array_delete(inv, idx, 1);

                            if (picked == undefined) picked = { name: "???" };
                            if (!is_struct(picked)) picked = { name: string(picked) };

                            app.domain.carry_active = true;
                            app.domain.carry_item = picked;
                            app.domain.carry_original_index = idx;

                            // Clamp scroll after removal
                            inv_count = array_length(inv);
                            content_h = PAD_TOP + PAD_BOT;
                            if (inv_count > 0) content_h += inv_count * ICON + max(0, inv_count - 1) * SPACING;
                            max_scroll = max(0, content_h - gh);
                            app.domain.inv_scroll_offset_px = clamp(app.domain.inv_scroll_offset_px, 0, max_scroll);
                        }
                    }
                }

                ui_consumed = true;
            }
        } else {
            // Click started outside column => cancel any drag state
            if (app.domain.inv_drag_active && !app.input.mouse_down_left()) {
                app.domain.inv_drag_active = false;
                app.domain.inv_drag_moved = false;
            }
        }

        // ----------------------------
        // World interactions while inventory is open:
        // - blocked only where covered by the panel
        // - allowed in the world area (right half), unless UI consumed or carrying
        // ----------------------------
        if (!ui_consumed && !app.domain.carry_active && mouse_in_world_area) {
            var hovered_item2 = hud_get_hovered_item(app, cam);
            var hovered_enemy2 = hud_get_hovered_enemy(app, cam);

            // HOLD: only while LMB is down AND cursor remains on the current target
            app.domain.player.attack_hold =
                mouse_check_button(mb_left)
                && is_struct(hovered_enemy2)
                && hovered_enemy2.id == app.domain.player.act_target_id;

            if (app.input.mouse_pressed_left()) {
                // Priority 1: items
                if (is_struct(hovered_item2)) {
                    app.ports.action.impl.player_try_pickup_item(hovered_item2.id);
                }
                // Priority 2: enemies
                else if (is_struct(hovered_enemy2)) {
                    combat_player_issue_attack_order(app.domain, hovered_enemy2.id);
                }
                // Priority 3: click-to-move
                else {
                    // click-to-move cancels combat + queued next action + pickup intent
                    app.domain.player.act_target_id = -1;
                    app.domain.player.attack_cmd = false;
                    app.domain.player.attack_hold = false;

                    app.domain.player.queued_attack_cmd = false;
                    app.domain.player.queued_target_id = -1;

                    app.domain.player.pickup_target_item_id = -1;

                    app.cmd.dispatch({
                        type: "cmd_click_move",
                        sx: msx,
                        sy: msy,
                        mode: app.view.mode,
                        cam: cam
                    });
                }
            }

            // HOLD-TO-MOVE: while holding LMB over empty world, continuously update destination.
            if (mouse_check_button(mb_left)
                && !is_struct(hovered_item2)
                && !is_struct(hovered_enemy2)) {

                // Treat as repeated click-to-move: cancels combat + queued next action + pickup intent
                app.domain.player.act_target_id = -1;
                app.domain.player.attack_cmd = false;
                app.domain.player.attack_hold = false;
                app.domain.player.queued_attack_cmd = false;
                app.domain.player.queued_target_id = -1;
                app.domain.player.pickup_target_item_id = -1;

                app.cmd.dispatch({
                    type: "cmd_click_move",
                    sx: msx,
                    sy: msy,
                    mode: app.view.mode,
                    cam: cam
                });
            }
        } else {
            // Inventory open but not interacting with world => don't stick attack hold
            app.domain.player.attack_hold = false;
        }
    }
    // ----------------------------
    // Normal gameplay when inventory is closed (existing behavior)
    // ----------------------------
    else {
        // Hovered entities
        var hovered_item = hud_get_hovered_item(app, cam);
        var hovered_enemy = hud_get_hovered_enemy(app, cam);

        // HOLD: only while LMB is down AND cursor remains on the current target
        app.domain.player.attack_hold =
            mouse_check_button(mb_left)
            && is_struct(hovered_enemy)
            && hovered_enemy.id == app.domain.player.act_target_id;

        // CLICK
        if (app.input.mouse_pressed_left()) {
            // Priority 1: items
            if (is_struct(hovered_item)) {
                app.ports.action.impl.player_try_pickup_item(hovered_item.id);
            }
            // Priority 2: enemies
            else if (is_struct(hovered_enemy)) {
                combat_player_issue_attack_order(app.domain, hovered_enemy.id);
            }
            // Priority 3: click-to-move
            else {
                // click-to-move cancels combat + queued next action + pickup intent
                app.domain.player.act_target_id = -1;
                app.domain.player.attack_cmd = false;
                app.domain.player.attack_hold = false;

                app.domain.player.queued_attack_cmd = false;
                app.domain.player.queued_target_id = -1;

                app.domain.player.pickup_target_item_id = -1;

                app.cmd.dispatch({
                    type: "cmd_click_move",
                    sx: device_mouse_x_to_gui(0),
                    sy: device_mouse_y_to_gui(0),
                    mode: app.view.mode,
                    cam: cam
                });
            }
        }

        // HOLD-TO-MOVE: while holding LMB over empty world, continuously update destination.
        if (mouse_check_button(mb_left)
            && !is_struct(hovered_item)
            && !is_struct(hovered_enemy)) {

            app.domain.player.act_target_id = -1;
            app.domain.player.attack_cmd = false;
            app.domain.player.attack_hold = false;
            app.domain.player.queued_attack_cmd = false;
            app.domain.player.queued_target_id = -1;
            app.domain.player.pickup_target_item_id = -1;

            app.cmd.dispatch({
                type: "cmd_click_move",
                sx: device_mouse_x_to_gui(0),
                sy: device_mouse_y_to_gui(0),
                mode: app.view.mode,
                cam: cam
            });
        }
    }

    app.ports.action.impl.step_simulation(1 / room_speed);
    app.domain.build_render_packets();
}

// Camera follows player using read-only query port
var pos = app.ports.query.impl.get_player_pos();

// When inventory is open, shift camera so the *visible* right half centers on the player.
// In screen space, player should sit at 75% of viewport width instead of 50%.
var cam_shift_px = (app.domain.inventory_open) ? (cam.vw * 0.25) : 0;

if (app.view.mode == "ortho") {
    cam.x = pos.x - cam_shift_px;
    cam.y = pos.y;
} else {
    var pproj = app.renderer.iso_project(pos.x, pos.y);
    cam.x = pproj.x - cam_shift_px;
    cam.y = pproj.y;
}
