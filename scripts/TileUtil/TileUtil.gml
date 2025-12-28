/// Tile helpers (orthographic world in pixels; tiles are ORTHO_TILE)

function tileutil_world_to_tile(_wx, _wy) {
    return {
        x: floor(_wx / ORTHO_TILE),
        y: floor(_wy / ORTHO_TILE)
    };
}

function tileutil_tile_to_world_center(_tx, _ty) {
    return {
        x: _tx * ORTHO_TILE + (ORTHO_TILE * 0.5),
        y: _ty * ORTHO_TILE + (ORTHO_TILE * 0.5)
    };
}

/// Chebyshev distance in tiles (radial for grid)
function tileutil_dist_chebyshev(_ax, _ay, _bx, _by) {
    return max(abs(_ax - _bx), abs(_ay - _by));
}

function tileutil_in_bounds(_lvl, _tx, _ty) {
    if (!is_struct(_lvl)) return false;
    return (_tx >= 0) && (_ty >= 0) && (_tx < _lvl.w) && (_ty < _lvl.h);
}
