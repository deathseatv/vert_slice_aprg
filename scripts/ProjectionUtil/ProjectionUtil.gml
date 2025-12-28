function ProjectionUtil() constructor {

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
