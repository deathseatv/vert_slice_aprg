function CommandBus() constructor {
    _handlers = {};

    register = function(_cmd_type, _fn) {
        _handlers[$ _cmd_type] = _fn;
    };

    dispatch = function(_cmd) {
        if (!is_struct(_cmd) || _cmd.type == undefined) return;
        var _fn = _handlers[$ _cmd.type];
        if (is_callable(_fn)) _fn(_cmd);
    };
}
