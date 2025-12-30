function CommandBus() constructor {
    _handlers = {};

    // Convenience command constructors (optional).
    // These keep call sites consistent without requiring callers to know handler shapes.
    cmd_drop_item_named = function(_name, _opts) {
        // _opts (optional):
        //  - mode: "near_player" (default) or "world"
        //  - sx, sy, cam, view_mode: optional; used when mode == "world"
        if (!is_struct(_opts)) _opts = {};
        if (!variable_struct_exists(_opts, "mode") || _opts.mode == undefined) _opts.mode = "near_player";

        // Safely pull optional fields without reading unset struct members.
        var sx = undefined;
        var sy = undefined;
        var cam = undefined;
        var view_mode = undefined;

        if (variable_struct_exists(_opts, "sx")) sx = _opts.sx;
        if (variable_struct_exists(_opts, "sy")) sy = _opts.sy;
        if (variable_struct_exists(_opts, "cam")) cam = _opts.cam;
        if (variable_struct_exists(_opts, "view_mode")) view_mode = _opts.view_mode;

        return {
            type: "cmd_drop_item_named",
            name: _name,
            mode: _opts.mode,
            sx: sx,
            sy: sy,
            cam: cam,
            view_mode: view_mode
        };
    };

    cmd_pickup_item = function(_item_id) {
        return { type: "cmd_pickup_item", item_id: _item_id };
    };

    cmd_attack_enemy = function(_enemy_id) {
        return { type: "cmd_attack_enemy", enemy_id: _enemy_id };
    };

    register = function(_cmd_type, _fn) {
        _handlers[$ _cmd_type] = _fn;
    };

    dispatch = function(_cmd) {
        if (!is_struct(_cmd) || _cmd.type == undefined) return;
        var _fn = _handlers[$ _cmd.type];
        if (is_callable(_fn)) _fn(_cmd);
    };
}
