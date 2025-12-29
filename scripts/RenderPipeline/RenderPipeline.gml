// ================================
// FILE: scripts/RenderPipeline/RenderPipeline.gml
// REPLACE ENTIRE FILE WITH THIS
// ================================
function RenderPipeline() constructor {
    iso_project = function(_wx, _wy) {
        var tx = _wx / ORTHO_TILE;
        var ty = _wy / ORTHO_TILE;

        var sx = (tx - ty) * ISO_HALF_W;
        var sy = (tx + ty) * ISO_HALF_H;

        return { x: sx, y: sy };
    };

    ortho_project = function(_wx, _wy) {
        // direct mapping: orthographic pixels
        return { x: _wx, y: _wy };
    };

    draw_packets = function(_packets, _cam, _mode) {
        var n = array_length(_packets);
        if (n <= 0) return;

        // Insertion sort by depth_key (no closures)
        for (var i = 1; i < n; i++) {
            var key = _packets[i];
            var j = i - 1;
            while (j >= 0 && _packets[j].depth_key > key.depth_key) {
                _packets[j + 1] = _packets[j];
                j--;
            }
            _packets[j + 1] = key;
        }

        for (var k = 0; k < n; k++) {
            var p = _packets[k];

            var proj;
            if (_mode == "ortho") proj = ortho_project(p.wx, p.wy);
            else proj = iso_project(p.wx, p.wy);

            var sx = proj.x - _cam.x + _cam.vw * 0.5;
            var sy = proj.y - _cam.y + _cam.vh * 0.5;

            if (p.kind == "tile") {
                if (_mode == "ortho") {
                    // top-left anchor; no -16
                    var x1 = round(sx) - 16;
                    var y1 = round(sy) - 16;
                    var x2 = x1 + ORTHO_TILE;
                    var y2 = y1 + ORTHO_TILE;

                    draw_set_color(c_black);
                    draw_rectangle(x1, y1, x2, y2, false);

                    draw_set_color(c_aqua);
                    draw_rectangle(x1, y1, x2, y2, true);
                    draw_set_color(c_white);
                } else {
                    // top vertex anchor; no sy -16
                    var _x = sx;
                    var _y = sy - 16;

                    var left_x  = _x - ISO_HALF_W;
                    var left_y  = _y + ISO_HALF_H;

                    var right_x = _x + ISO_HALF_W;
                    var right_y = _y + ISO_HALF_H;

                    var bot_x   = _x;
                    var bot_y   = _y + (ISO_HALF_H * 2);

                    draw_set_color(c_white);
                    draw_line(_x, _y, right_x, right_y);
                    draw_line(right_x, right_y, bot_x, bot_y);
                    draw_line(bot_x, bot_y, left_x, left_y);
                    draw_line(left_x, left_y, _x, _y);
                }
            }
            else if (p.kind == "target") {
                draw_set_color(c_yellow);
                draw_circle(round(sx), round(sy), 5, false);
                draw_set_color(c_white);
            }
            else if (p.kind == "player") {
                draw_set_color(c_lime);
                draw_circle(round(sx), round(sy - 20), 6, false);
                draw_line(round(sx), round(sy - 14), round(sx), round(sy));
                draw_set_color(c_white);
            }
            else if (p.kind == "enemy") {
                draw_set_color(c_red);
                if (_mode == "ortho") {
                    var s = 8;
                    draw_rectangle(round(sx - s), round(sy - s), round(sx + s), round(sy + s), false);
                } else {
                    draw_circle(round(sx), round(sy), 6, false);
                }
                draw_set_color(c_white);
            }
            else if (p.kind == "item") {
                // Simple pickup marker
                draw_set_color(c_white);
                if (_mode == "ortho") {
                    draw_circle(round(sx), round(sy), 4, false);
                    draw_text(round(sx) + 8, round(sy) - 8, p.name);
                } else {
                    draw_circle(round(sx), round(sy), 4, false);
                    draw_text(round(sx) + 8, round(sy) - 8, p.name);
                }
            }
        }
    };
}
