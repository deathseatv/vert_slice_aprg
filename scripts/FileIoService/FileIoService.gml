function FileIoService() constructor {
    write_text = function(_relpath, _text) {
        var f = file_text_open_write(_relpath);
        file_text_write_string(f, _text);
        file_text_close(f);
        return true;
    };

    read_text = function(_relpath) {
        if (!file_exists(_relpath)) return "";
        var f = file_text_open_read(_relpath);
        var s = "";
        while (!file_text_eof(f)) {
            s += file_text_read_string(f);
            if (!file_text_eof(f)) file_text_readln(f);
        }
        file_text_close(f);
        return s;
    };
}
