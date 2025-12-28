function SaveService(_fileio) constructor {
    io = _fileio;
    VERSION = 1;

    _path_for_slot = function(_slot) {
        return "save_slot_" + string(_slot) + ".json";
    };

    save_slot = function(_slot, _profile_struct, _character_struct) {
        var payload = {
            version: VERSION,
            saved_at_utc: date_current_datetime(), // simple stamp
            profile: _profile_struct,
            character: _character_struct
        };
        return io.write_text(_path_for_slot(_slot), json_stringify(payload));
    };

    load_slot = function(_slot) {
        var txt = io.read_text(_path_for_slot(_slot));
        if (txt == "") return undefined;

        var data = json_parse(txt);
        if (!is_struct(data)) return undefined;

        // versioning hook
        if (data.version == undefined) data.version = 0;
        if (data.version != VERSION) {
            // For now: reject; later: migrate.
            return undefined;
        }
        return data;
    };
}
