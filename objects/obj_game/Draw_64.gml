// objects/obj_game/Draw_64.gml
// obj_game : Draw GUI Event

var app = global.app;

// Clear UI space / header
draw_text(16, 16, "GAMEPLAY  Esc: Menu  S: Save Slot1  L: Load Slot1");
draw_text(16, 32, "View: " + app.view.mode + "  P: Toggle");

// ----------------------------
// HUD: Player HP + hovered enemy HP (pure UI)
// ----------------------------
var hud_w = 200;
var hud_h = 10;
var hud_x = display_get_gui_width() - (hud_w + 16);
var hud_y = 16;

// Render consumes render packets only
var packets = app.ports.render.impl.get_packets();
app.renderer.draw_packets(packets, cam, app.view.mode);

// ----------------------------
// Floating unit action text (world -> screen)
// ----------------------------
draw_set_color(c_white);

// player
var p = app.domain.player;
var ps = combat_world_to_screen(app, cam, p.x, p.y);
draw_text(ps.x + 10, ps.y - 52, "P " + combat_act_to_text(p.act));

// enemies
var en = array_length(app.domain.enemies);
for (var i = 0; i < en; i++) {
    var e = app.domain.enemies[i];
    var es = combat_world_to_screen(app, cam, e.x, e.y);
    draw_text(es.x + 10, es.y - 52, "E" + string(e.id) + " " + combat_act_to_text(e.act));
}

// Diagnostics overlay
app.diag.draw(16, 48);

// Global hotkeys handled either here or in state
if (app.input.pressed("load")) {
    app.cmd.dispatch({ type: "cmd_load_character", slot: 1 });
}

draw_text(16, 320, "Enemy count: " + string(array_length(app.domain.enemies)));

// ----------------------------
// Player numeric location (start at y=256)
// ----------------------------
var pos = app.ports.query.impl.get_player_pos();
var px = pos.x;
var py = pos.y;

draw_text(16, 256, "Player World: " + string(round(px)) + ", " + string(round(py)));

var ptx = floor(px / ORTHO_TILE);
var pty = floor(py / ORTHO_TILE);
draw_text(16, 272, "Player Tile: " + string(ptx) + ", " + string(pty));

if (app.view.mode == "ortho") {
    draw_text(16, 288, "Player Screen Ortho: " + string(round(px)) + ", " + string(round(py)));
} else {
    var pproj = app.renderer.iso_project(px, py);
    draw_text(16, 288, "Player Screen Iso: " + string(round(pproj.x)) + ", " + string(round(pproj.y)));
}

// ----------------------------
// Mouse readout (active view only)
// ----------------------------
var msx = device_mouse_x_to_gui(0);
var msy = device_mouse_y_to_gui(0);

var w; // world orthographic pixels
if (app.view.mode == "ortho") {
    w = app.proj.screen_to_world_ortho(msx, msy, cam);
} else {
    w = app.proj.screen_to_world_iso(msx, msy, cam);
}

var hovered = hud_get_hovered_enemy_from_world(app, w.x, w.y);

// Draw HUD after world rendering so it stays on top
hud_draw_hp_bar(hud_x, hud_y + 32, hud_w, hud_h,
                app.domain.player.hp, app.domain.player.hp_max,
                "Player");

if (is_struct(hovered)) {
    hud_draw_hp_bar(hud_x, hud_y + 64, hud_w, hud_h,
                    hovered.hp, hovered.hp_max,
                    "Enemy " + string(hovered.id));
}

var mtx = floor(w.x / ORTHO_TILE);
var mty = floor(w.y / ORTHO_TILE);

var base_y = 360;
draw_text(16, base_y + 0,  "Mouse GUI: " + string(msx) + ", " + string(msy));
draw_text(16, base_y + 16, "Mouse World (" + app.view.mode + "): " + string(round(w.x)) + ", " + string(round(w.y)));
draw_text(16, base_y + 32, "Mouse Tile  (" + app.view.mode + "): " + string(mtx) + ", " + string(mty));

// Console overlay on top half
if (app.console.open) {
    var gw = display_get_gui_width();
    var gh = display_get_gui_height();
    app.console.draw_gui(0, 0, gw, gh * 0.5);
}
