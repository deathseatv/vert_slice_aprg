function RngSeedService() constructor {
    next_seed = function() {
        // Deterministic enough for saves/replay; replace later if desired.
        return irandom_range(1, 2147483646);
    };

    with_seed = function(_seed, _fn) {
        var _old = random_get_seed();
        random_set_seed(_seed);
        var _result = _fn();
        random_set_seed(_old);
        return _result;
    };
}
