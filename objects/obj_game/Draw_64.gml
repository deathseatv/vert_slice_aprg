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

// Hovered enemy HP (if any)
if (is_struct(hovered_enemy)) {
    // Some enemy structs may not include a display name; avoid "field not set" crashes.
    var enemy_label = "Enemy";
    if (variable_struct_exists(hovered_enemy, "name")) enemy_label = hovered_enemy.name;
    else if (variable_struct_exists(hovered_enemy, "title")) enemy_label = hovered_enemy.title;
    else if (variable_struct_exists(hovered_enemy, "kind")) enemy_label = string(hovered_enemy.kind);
    else if (variable_struct_exists(hovered_enemy, "type")) enemy_label = string(hovered_enemy.type);

    hud_draw_hp_bar(hud_x, hud_y + 64, hud_w, hud_h,
                    hovered_enemy.hp, hovered_enemy.hp_max,
                    enemy_label);
}

// Inventory UI (controller draw)
invui_get_controller().draw(app);

// Console overlay on top half
if (app.console.open) {
    var gw2 = display_get_gui_width();
    var gh2 = display_get_gui_height();
    app.console.draw_gui(0, 0, gw2, gh2 * 0.5);
}
