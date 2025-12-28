function StateGameplay(_ctx) constructor {
    ctx = _ctx;
    name = "Gameplay";

    enter = function() {
        ctx.diag.log("Gameplay enter");
        room_goto(rm_game);
    };

    step = function() {
        if (ctx.input.pressed("cancel")) {
            ctx.cmd.dispatch({ type: "cmd_return_to_menu" });
        }
        if (ctx.input.pressed("save")) {
            ctx.cmd.dispatch({ type: "cmd_save_character", slot: 1 });
        }
    };

    draw = function() {};
    _exit = function() { ctx.diag.log("Gameplay exit"); };
}
