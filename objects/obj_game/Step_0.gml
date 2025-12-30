// ================================
// FILE: objects/obj_game/Step_0.gml
// REPLACE ENTIRE FILE WITH THIS
// ================================
// objects/obj_game/Step_0.gml
var app = global.app;

// Keep camera viewport dimensions current (used by both UI + camera follow)
cam.vw = display_get_gui_width();
cam.vh = display_get_gui_height();

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

    // NOTE: console pending_* bridging is handled ONLY by AppBoot.
} else {
    // ----------------------------
    // View toggle (Tab) (always allowed when console is closed)
    // ----------------------------
    if (app.input.pressed("toggle_view")) {
        app.cmd.dispatch({ type: "cmd_toggle_view" });
    }

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

            // Reset scroll/drag when closing
            app.domain.inv_scroll_offset_px = 0;
            app.domain.inv_drag_active = false;
            app.domain.inv_drag_moved = false;
        }
    }

    // Close inventory on Escape (only if console is closed)
    if (keyboard_check_pressed(vk_escape) && app.domain.inventory_open) {
        // Return carry if needed
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

    var msx = device_mouse_x_to_gui(0);
    var msy = device_mouse_y_to_gui(0);
    var mouse = { sx: msx, sy: msy };

    // ----------------------------
    // Inventory UI controller (input)
    // ----------------------------
    var ui = invui_get_controller();
    var ui_out = ui.step(app, cam, mouse);

    // Execute any world intent produced by UI (Phase 5: via CommandBus only)
    if (is_struct(ui_out.intent)) {
        // Inventory drop is player-centric (Phase 4): ignore cursor position.
        if (ui_out.intent.type == "inv_drop_item_at_cursor_named") {
            app.cmd.dispatch(app.cmd.cmd_drop_item_named(ui_out.intent.name, { mode: "near_player" }));
        }
    }

    // ----------------------------
    // Gameplay input (only if UI didn't consume)
    // ----------------------------
    if (!ui_out.ui_consumed) {
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
                app.cmd.dispatch(app.cmd.cmd_pickup_item(hovered_item.id));
            }
            // Priority 2: enemies
            else if (is_struct(hovered_enemy)) {
                app.cmd.dispatch(app.cmd.cmd_attack_enemy(hovered_enemy.id));
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
                sx: msx,
                sy: msy,
                mode: app.view.mode,
                cam: cam
            });
        }
    } else {
        // UI consumed this frame => don't stick gameplay holds
        app.domain.player.attack_hold = false;
    }
}

// ------------------------------------------------------------
// Authoritative per-frame orchestrator
// - Runs simulation step
// - Builds render packets
// ------------------------------------------------------------
app.step();

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
