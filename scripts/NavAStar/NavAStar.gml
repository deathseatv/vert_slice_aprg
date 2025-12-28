/// Returns an array of tiles [{x,y}, ...] excluding the start tile and including the goal tile.
/// Returns undefined if no path.
/// Uses _nav.can_walk(tx,ty) and level bounds.

function nav_astar_tiles(_nav, _lvl, _sx, _sy, _gx, _gy) {
    if (!is_struct(_lvl)) return undefined;
    if (!is_struct(_nav)) return undefined;

    if (!tileutil_in_bounds(_lvl, _sx, _sy)) return undefined;
    if (!tileutil_in_bounds(_lvl, _gx, _gy)) return undefined;
    if (!_nav.can_walk(_gx, _gy)) return undefined;

    if (_sx == _gx && _sy == _gy) {
        return []; // already there
    }

    var w = _lvl.w;
    var h = _lvl.h;
    var total = w * h;

    var INF = 1000000000;

    var g = array_create(total, INF);
    var f = array_create(total, INF);
    var came = array_create(total, -1);
    var closed = array_create(total, false);
    var in_open = array_create(total, false);

    var start_i = _sx + _sy * w;
    var goal_i  = _gx + _gy * w;

    g[start_i] = 0;
    f[start_i] = tileutil_dist_chebyshev(_sx, _sy, _gx, _gy);

    var open = [];
    array_push(open, start_i);
    in_open[start_i] = true;

    // 8-direction neighbors
    var nx_off = [ -1,  0,  1, -1, 1, -1, 0, 1 ];
    var ny_off = [ -1, -1, -1,  0, 0,  1, 1, 1 ];

    while (array_length(open) > 0) {
        // find lowest f in open (linear scan; map is small)
        var best_k = 0;
        var best_i = open[0];
        var best_f = f[best_i];

        var open_n = array_length(open);
        for (var k = 1; k < open_n; k++) {
            var ii = open[k];
            var ff = f[ii];
            if (ff < best_f) {
                best_f = ff;
                best_i = ii;
                best_k = k;
            }
        }

        // pop best
        array_delete(open, best_k, 1);
        in_open[best_i] = false;

        if (best_i == goal_i) {
            // reconstruct path (goal -> start), then reverse
            var rev = [];
            var cur = goal_i;

            while (cur != start_i) {
                var cx = cur mod w;
                var cy = cur div w;
                array_push(rev, { x: cx, y: cy });

                cur = came[cur];
                if (cur == -1) return undefined; // safety
            }

            // reverse into forward path
            var out = [];
            for (var r = array_length(rev) - 1; r >= 0; r--) {
                array_push(out, rev[r]);
            }
            return out;
        }

        closed[best_i] = true;

        var cx = best_i mod w;
        var cy = best_i div w;

        for (var n = 0; n < 8; n++) {
            var tx = cx + nx_off[n];
            var ty = cy + ny_off[n];

            if (!tileutil_in_bounds(_lvl, tx, ty)) continue;
            if (!_nav.can_walk(tx, ty)) continue;

            var ni = tx + ty * w;
            if (closed[ni]) continue;

            var tentative_g = g[best_i] + 1;

            if (tentative_g < g[ni]) {
                came[ni] = best_i;
                g[ni] = tentative_g;
                f[ni] = tentative_g + tileutil_dist_chebyshev(tx, ty, _gx, _gy);

                if (!in_open[ni]) {
                    array_push(open, ni);
                    in_open[ni] = true;
                }
            }
        }
    }

    return undefined;
}
