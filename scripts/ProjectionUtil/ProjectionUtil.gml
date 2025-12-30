function ProjectionUtil() constructor {

    /// Convert GUI/screen coords to world coords based on view mode ("ortho" or "iso").
    gui_to_world = function(_sx, _sy, _cam, _mode) {
        if (_mode == "ortho") return screen_to_world_ortho(_sx, _sy, _cam);
        return screen_to_world_iso(_sx, _sy, _cam);
    };

    /// Convert GUI/screen coords to the world position at the center of the nearest tile.
    /// Returns { wx, wy, tx, ty }.
    /// If a level struct is provided, tile coords are clamped to [0..w-1],[0..h-1].
    gui_to_tile_center_world = function(_sx, _sy, _cam, _mode, _lvl) {
        var w = gui_to_world(_sx, _sy, _cam, _mode);
        var t = tileutil_world_to_nearest_tile(w.x, w.y);
        var tx = t.x;
        var ty = t.y;

        if (is_struct(_lvl)) {
            tx = clamp(tx, 0, _lvl.w - 1);
            ty = clamp(ty, 0, _lvl.h - 1);
        }

        var c = tileutil_tile_to_world_center(tx, ty);
        return { wx: c.x, wy: c.y, tx: tx, ty: ty };
    };

    screen_to_world_ortho = function(_sx, _sy, _cam) {
        var wx = _sx + _cam.x - (_cam.vw * 0.5);
        var wy = _sy + _cam.y - (_cam.vh * 0.5);
        return { x: wx, y: wy };
    };

    screen_to_world_iso = function(_sx, _sy, _cam) {
        var sx = _sx + _cam.x - (_cam.vw * 0.5);
        var sy = _sy + _cam.y - (_cam.vh * 0.5);

        var a = sx / ISO_HALF_W;
        var b = sy / ISO_HALF_H;

        var tx = (a + b) * 2;
        var ty = (b - a) * 2;

        var wx = tx * ORTHO_TILE;
        var wy = ty * ORTHO_TILE;

        return { x: wx, y: wy };
    };
}
