function Diagnostics() constructor {
    lines = [];
    max_lines = 10;

    log = function(_s) {
        array_push(lines, string(_s));
        while (array_length(lines) > max_lines) array_delete(lines, 0, 1);
    };

    draw = function(_x, _y) {
        var yy = _y;
        var n = array_length(lines);
        for (var i = 0; i < n; i++) {
            draw_text(_x, yy, lines[i]);
            yy += 14;
        }
    };
}
