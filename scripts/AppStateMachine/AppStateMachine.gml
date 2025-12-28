function AppStateMachine() constructor {
    _state = undefined;

    set = function(_s) {
        if (is_struct(_state) && is_callable(_state._exit)) _state._exit();
        _state = _s;
        if (is_struct(_state) && is_callable(_state.enter)) _state.enter();
    };

    step = function() {
        if (is_struct(_state) && is_callable(_state.step)) _state.step();
    };

    draw = function() {
        if (is_struct(_state) && is_callable(_state.draw)) _state.draw();
    };

    name = function() {
        return (is_struct(_state) && _state.name != undefined) ? _state.name : "none";
    };
}
