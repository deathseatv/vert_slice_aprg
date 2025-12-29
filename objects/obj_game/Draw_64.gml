// ================================
// FILE: objects/obj_game/Draw_64.gml
// REPLACE ENTIRE FILE WITH THIS
// ================================
// objects/obj_game/Draw_64.gml
var app = global.app;

// Clear background
draw_clear(c_black);

// Draw world via render packets
app.renderer.draw_packets(app.domain._packets, cam, app.view.mode);

// HUD overlay (GUI coordinates)
var gw = display_get_gui_width();
var gh = display_get_gui_height();

// Hovered enemy for HUD display
var hovered_enemy = hud_get_hovered_enemy(app, cam);

// Player HP
var hud_x = 16;
var hud_y = 16;
var hud_w = 160;
var hud_h = 16;

hud_draw_hp_bar(hud_x, hud_y + 32, hud_w, hud_h,
                app.domain.player.hp, app.domain.player.hp_max,
                "Player");

if (is_struct(hovered_enemy)) {
    hud_draw_hp_bar(hud_x, hud_y + 64, hud_w, hud_h,
                    hovered_enemy.hp, hovered_enemy.hp_max,
                    "Enemy " + string(hovered_enemy.id));
}

// Debug mouse info
var msx = device_mouse_x_to_gui(0);
var msy = device_mouse_y_to_gui(0);

var w;
if (app.view.mode == "ortho") w = app.proj.screen_to_world_ortho(msx, msy, cam);
else w = app.proj.screen_to_world_iso(msx, msy, cam);

var mtx = floor(w.x / ORTHO_TILE);
var mty = floor(w.y / ORTHO_TILE);

var base_y = 360;
draw_text(16, base_y + 0,  "Mouse GUI: " + string(msx) + ", " + string(msy));
draw_text(16, base_y + 16, "Mouse World (" + app.view.mode + "): " + string(round(w.x)) + ", " + string(round(w.y)));
draw_text(16, base_y + 32, "Mouse Tile  (" + app.view.mode + "): " + string(mtx) + ", " + string(mty));

// ----------------------------
// Inventory UI (left half, solid gray)
// - Icon column on right edge of panel (56px wide)
// - Drag-scroll icon list
// - Cursor-carry draws icon at mouse position
// ----------------------------
if (app.domain.inventory_open) {
    // solid gray rectangle covering left 50%
    var panel_w = gw * 0.5;
    draw_set_color(make_color_rgb(96, 96, 96));
    draw_rectangle(0, 0, panel_w, gh, false);

    // Title + text list (existing)
    draw_set_color(c_white);
    draw_text(16, 80, "INVENTORY");

    var inv = app.domain.player.inventory;
    var inv_y = 104;

    if (!is_array(inv) || array_length(inv) <= 0) {
        draw_text(16, inv_y, "(empty)");
    } else {
        for (var ii = 0; ii < array_length(inv); ii++) {
            var row = inv[ii];
            var name = (is_struct(row) && row.name != undefined) ? row.name : "???";
            draw_text(16, inv_y, "- " + string(name));
            inv_y += 16;
        }
    }

    // Icon column
    var col_w = 56;
    var col_x1 = panel_w - col_w;
    var col_x2 = panel_w;

    draw_set_color(make_color_rgb(72, 72, 72));
    draw_rectangle(col_x1, 0, col_x2, gh, false);

    // Column layout constants (must match step)
    var ICON = 32;
    var PAD_TOP = 12;
    var SPACING = 8;
    var pitch = ICON + SPACING;

    var icon_x = col_x1 + floor((col_w - ICON) * 0.5);
    var scroll = app.domain.inv_scroll_offset_px;

    if (is_array(inv)) {
        var n = array_length(inv);
        for (var i = 0; i < n; i++) {
            var _y = floor(PAD_TOP + i * pitch - scroll);
            var y2 = _y + ICON;

            // skip offscreen (simple clip)
            if (y2 < 0) continue;
            if (_y > gh) break;

            // draw placeholder icon
            draw_set_color(make_color_rgb(160, 160, 160));
            draw_rectangle(icon_x, _y, icon_x + ICON, _y + ICON, false);

            draw_set_color(c_black);
            draw_rectangle(icon_x, _y, icon_x + ICON, _y + ICON, true);

            // label: first letter
            var nm = " ?";
            if (is_struct(inv[i]) && inv[i].name != undefined) nm = string(inv[i].name);
            else if (inv[i] != undefined) nm = string(inv[i]);

            var ch = string_char_at(nm, 1);
            draw_set_color(c_white);
            draw_text(icon_x + 10, _y + 8, string_upper(ch));
        }
    }

    // Carried icon follows cursor in GUI coordinates
    if (app.domain.carry_active) {
        var cx = floor(msx - 16);
        var cy = floor(msy - 16);

        draw_set_color(make_color_rgb(220, 220, 220));
        draw_rectangle(cx, cy, cx + 32, cy + 32, false);

        draw_set_color(c_black);
        draw_rectangle(cx, cy, cx + 32, cy + 32, true);

        var cnm = " ?";
        if (is_struct(app.domain.carry_item) && app.domain.carry_item.name != undefined) cnm = string(app.domain.carry_item.name);
        var cch = string_char_at(cnm, 1);

        draw_set_color(c_white);
        draw_text(cx + 10, cy + 8, string_upper(cch));
    }
}

// Console overlay on top half
if (app.console.open) {
    var gw2 = display_get_gui_width();
    var gh2 = display_get_gui_height();
    app.console.draw_gui(0, 0, gw2, gh2 * 0.5);
}
