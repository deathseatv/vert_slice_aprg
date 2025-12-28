function StateReturnToMenu(_ctx) constructor {
    ctx = _ctx;
    name = "ReturnToMenu";

    enter = function() {
        ctx.diag.log("Returning to menu");
        room_goto(rm_boot);
    };

    step = function() {
        ctx.sm.set(ctx.states.menu);
    };

    draw = function() {};
    _exit = function() {};
}
