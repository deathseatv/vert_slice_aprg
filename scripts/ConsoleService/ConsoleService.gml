function ConsoleService() constructor {
    open = false;
    input_line = "";
    lines = [];
    max_lines = 200;

	pending_spawn = undefined; // { tx, ty } set when parsed, consumed by AppBoot

    // caret blink (optional)
    _blink_t = 0;
    _caret_on = true;

    _cap_lines = function() {
        while (array_length(lines) > max_lines) {
            array_delete(lines, 0, 1);
        }
    };

    _push_line = function(_s) {
        array_push(lines, string(_s));
        _cap_lines();
    };

    _push_multiline = function(_text) {
        var s = string(_text);
        var start = 1;
        var len = string_length(s);

        // split on \n without using closures
        for (var i = 1; i <= len; i++) {
            if (string_char_at(s, i) == "\n") {
                _push_line(string_copy(s, start, i - start));
                start = i + 1;
            }
        }
        if (start <= len) {
            _push_line(string_copy(s, start, len - start + 1));
        }
        if (len == 0) _push_line("");
    };

    toggle = function() {
        if (open) close(); else open_console();
    };

    open_console = function() {
        open = true;
        keyboard_string = "";
        input_line = "";
        _push_line("Console opened. Type /help");
    };

    close = function() {
        open = false;
        keyboard_string = "";
        input_line = "";
    };

    clear = function() {
        lines = [];
    };

    print = function(_text) {
        _push_multiline(_text);
    };

    submit = function(_line) {
        var line = string(_line);
        // trim basic (spaces)
        line = string_trim(line);

        if (line == "") return;

        _push_line("> " + line);

        if (line == "/help") {
            print(
                "Commands:\n" +
                "/help  - show this message\n" +
                "/clear - clear console\n" +
                "/echo <text> - print text"
            );
            return;
        }

        if (line == "/clear") {
            clear();
            return;
        }

        if (string_copy(line, 1, 5) == "/echo") {
            var rest = string_trim(string_delete(line, 1, 5));
            print(rest);
            return;
        }

				// /spawn enemy tx ty
		if (string_copy(line, 1, 6) == "/spawn") {
		    // Expect: /spawn enemy <tx> <ty>
		    // Simple tokenization without closures
		    var s = line;
		    var len = string_length(s);

		    // collect tokens split by spaces
		    var tokens = [];
		    var tok = "";
		    for (var i = 1; i <= len; i++) {
		        var ch = string_char_at(s, i);
		        if (ch == " ") {
		            if (tok != "") { array_push(tokens, tok); tok = ""; }
		        } else {
		            tok += ch;
		        }
		    }
		    if (tok != "") array_push(tokens, tok);

		    if (array_length(tokens) != 4) {
		        print("Usage: /spawn enemy <tx> <ty>");
		        return;
		    }

		    if (tokens[1] != "enemy") {
		        print("Usage: /spawn enemy <tx> <ty>");
		        return;
		    }

		    var txs = tokens[2];
		    var tys = tokens[3];

		    // Validate ints
		    if (!string_digits(txs) || !string_digits(tys)) {
		        print("Usage: /spawn enemy <tx> <ty> (tx,ty must be integers)");
		        return;
		    }

		    var tx = real(txs);
		    var ty = real(tys);

		    pending_spawn = { tx: tx, ty: ty };
		    print("Spawn request enemy at tile " + string(tx) + " " + string(ty));
		    return;
		}

        print("Unknown command: " + line);
    };

    // Called only while console is open
    step = function() {
        // caret blink
        _blink_t += 1;
        if (_blink_t >= 30) { // ~0.5s at 60fps
            _blink_t = 0;
            _caret_on = !_caret_on;
        }

        // keyboard_string is managed by GameMaker input system
        input_line = keyboard_string;
    };

    draw_gui = function(_x, _y, _w, _h) {
        // dark gray top half
        draw_set_color(make_color_rgb(32, 32, 32));
        draw_rectangle(_x, _y, _x + _w, _y + _h, false);

        draw_set_color(c_white);

        var pad = 8;
        var line_h = 14;
        var text_x = _x + pad;
        var text_y = _y + pad;

        // visible area excluding prompt line
        var prompt_y = _y + _h - pad - line_h;
        var max_visible = floor((prompt_y - text_y) / line_h);
        if (max_visible < 0) max_visible = 0;

        // draw last max_visible lines
        var total = array_length(lines);
        var start = total - max_visible;
        if (start < 0) start = 0;

        var yy = text_y;
        for (var i = start; i < total; i++) {
            draw_text(text_x, yy, lines[i]);
            yy += line_h;
        }

        // prompt
        var caret = (_caret_on) ? "_" : " ";
        draw_text(text_x, prompt_y, "> " + input_line + caret);
    };
}
