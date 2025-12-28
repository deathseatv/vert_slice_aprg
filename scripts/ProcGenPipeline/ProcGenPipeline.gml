function ProcGenPipeline(_rng) constructor {
    rng = _rng;

    generate_blueprint = function(_seed) {
        // Avoid closures entirely: do deterministic seeding inline
        var old = random_get_seed();
        random_set_seed(_seed);

        var bp = {
            seed: _seed,
            w: 24,
            h: 24
        };

        random_set_seed(old);
        return bp;
    };

    validate_repair = function(_bp) {
        if (_bp.w < 8) _bp.w = 8;
        if (_bp.h < 8) _bp.h = 8;
        return _bp;
    };
}
