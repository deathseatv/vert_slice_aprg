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

    // simulation continues
    app.ports.action.impl.step_simulation(1 / room_speed);
    app.domain.build_render_packets();
} else {
    // ----------------------------
    // Inventory UI input
    // ----------------------------
    if (app.input.pressed("toggle_inventory")) {
        app.domain.inventory_open = !app.domain.inventory_open;
    }
    if (app.domain.inventory_open && keyboard_check_pressed(vk_escape)) {
        app.domain.inventory_open = false;
    }

    // normal gameplay input
    if (app.input.pressed("toggle_view")) {
        app.cmd.dispatch({ type: "cmd_toggle_view" });
    }

    // If inventory is open: no world clicking / combat / pickup
    if (!app.domain.inventory_open) {
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
    } else {
        // Inventory open: ensure we don't stick attack hold
        app.domain.player.attack_hold = false;
    }

    app.ports.action.impl.step_simulation(1 / room_speed);
    app.domain.build_render_packets();
}

// Camera follows player using read-only query port
var pos = app.ports.query.impl.get_player_pos();

if (app.view.mode == "ortho") {
    cam.x = pos.x;
    cam.y = pos.y;
} else {
    var pproj = app.renderer.iso_project(pos.x, pos.y);
    cam.x = pproj.x;
    cam.y = pproj.y;
}
