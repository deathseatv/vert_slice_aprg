// ================================
// FILE: scripts/InputService/InputService.gml
// REPLACE ENTIRE FILE WITH THIS
// ================================
function InputService() constructor {
    // Minimal action mapping; later: rebinds + devices.
    bindings = {
        confirm: vk_enter,
        cancel: vk_escape,
        up: vk_up,
        down: vk_down,
        left: vk_left,
        right: vk_right,
        save: ord("S"),
        load: ord("L"),
        toggle_view: ord("P"),
        cancel_move: vk_escape,

        toggle_inventory: ord("I"),

        toggle_console: vk_f3, // tilde
        console_close: vk_escape
    };

    pressed = function(_action) {
        var k = bindings[$ _action];
        return (k != undefined) ? keyboard_check_pressed(k) : false;
    };

    down = function(_action) {
        var k = bindings[$ _action];
        return (k != undefined) ? keyboard_check(k) : false;
    };

    mouse_pressed_left = function() {
        return mouse_check_button_pressed(mb_left);
    };
}
