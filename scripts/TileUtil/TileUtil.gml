// ================================
// FILE: scripts/TileUtil/TileUtil.gml
// REPLACE ENTIRE FILE WITH THIS
// ================================
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

/// Nearest tile (by nearest tile center), not "containing tile"
function tileutil_world_to_nearest_tile(_wx, _wy) {
    // Centers are at (tx*ORTHO_TILE + ORTHO_TILE*0.5)
    // Solve for tx: tx = round((wx - half)/tile)
    var half = ORTHO_TILE * 0.5;
    return {
        x: round((_wx - half) / ORTHO_TILE),
        y: round((_wy - half) / ORTHO_TILE)
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
