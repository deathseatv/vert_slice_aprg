function EventBus() constructor {
    _subs = {};

    subscribe = function(_topic, _fn) {
        if (!is_struct(_subs)) _subs = {};
        if (_subs[$ _topic] == undefined) _subs[$ _topic] = [];
        array_push(_subs[$ _topic], _fn);
    };

    publish = function(_topic, _payload) {
        var _arr = _subs[$ _topic];
        if (_arr == undefined) return;
        var _n = array_length(_arr);
        for (var i = 0; i < _n; i++) {
            var _fn = _arr[i];
            if (is_callable(_fn)) _fn(_payload);
        }
    };
}
