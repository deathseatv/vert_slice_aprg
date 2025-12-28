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
    // normal gameplay input (view toggle, click-to-move)
    if (app.input.pressed("toggle_view")) {
        app.cmd.dispatch({ type: "cmd_toggle_view" });
    }

    if (app.input.mouse_pressed_left()) {
        app.cmd.dispatch({
            type: "cmd_click_move",
            sx: device_mouse_x_to_gui(0),
            sy: device_mouse_y_to_gui(0),
            mode: app.view.mode,
            cam: cam
        });
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
