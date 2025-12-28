function StateMainMenu(_ctx) constructor {
    ctx = _ctx; // capture once
    name = "MainMenu";

    enter = function() {
        ctx.diag.log("MainMenu enter");
    };

    step = function() {
        if (ctx.input.pressed("confirm")) {
            var seed = ctx.rng.next_seed();
            ctx.cmd.dispatch({ type: "cmd_start_game", seed: seed });
        }

        if (ctx.input.pressed("load")) {
            ctx.cmd.dispatch({ type: "cmd_load_character", slot: 1 });
        }
    };

    draw = function() {
        draw_text(24, 24, "MAIN MENU");
        draw_text(24, 44, "Enter: New Game");
        draw_text(24, 60, "L: Load Slot 1");
        draw_text(24, 76, "Esc: Quit");
        ctx.diag.draw(24, 110);

        if (ctx.input.pressed("cancel")) game_end();
    };

    _exit = function() {
        ctx.diag.log("MainMenu exit");
    };
}
