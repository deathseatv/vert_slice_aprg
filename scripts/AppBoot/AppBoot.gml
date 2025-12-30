function AppBoot() constructor {
    // stable self reference for closures
    var app = self;
    // Infrastructure
    cfg = new ConfigDataLoading();
    assets = new AssetRegistry();
    rng = new RngSeedService();
    time = new SchedulerTime();
    diag = new Diagnostics();

    // Messaging
    eb = new EventBus();
    cmd = new CommandBus();

    // Services
    input = new InputService();
    fileio = new FileIoService();
    save = new SaveService(fileio);
	console = new ConsoleService();

    // Procgen + Domain
    procgen = new ProcGenPipeline(rng);
    domain = new DomainGame(eb, procgen);

    // Ports (wrappers)
    ports = {
        query: new IWorldQuery(domain.world_query),
        action: new IAction(domain.actions),
        snap: new ISnapshot(domain.snapshot),
        render: new IRenderData(domain.render_data),
        nav: new INavigation(domain.navigation)
    };

    // Renderer (outside domain)
    renderer = new RenderPipeline();
	proj = new ProjectionUtil();
	view = { mode: "iso" }; // NEW: "iso" or "ortho"

    // App state machine
    sm = new AppStateMachine();

    // State instances
    states = {
        menu: undefined,
        gameplay: undefined,
        return_to_menu: undefined
    };

    // Shared context passed to states
    ctx = {
        cfg: cfg, assets: assets, rng: rng, time: time, diag: diag,
        eb: eb, cmd: cmd,
        input: input, save: save,
        ports: ports,
        sm: sm,
        states: states,
		view: view,
		proj: proj,
		console: console,
    };

    // Build states
    states.menu = new StateMainMenu(ctx);
    states.gameplay = new StateGameplay(ctx);
    states.return_to_menu = new StateReturnToMenu(ctx);

    // Command handlers (the only write path into domain is via IAction)
    cmd.register("cmd_start_game", function(_c) {
        ports.action.impl.start_game(_c.seed);
        sm.set(states.gameplay);
    });

    cmd.register("cmd_save_character", function(_c) {
        var profile = { version: 1 }; // stub
        var character = ports.snap.impl.make_character();
        save.save_slot(_c.slot, profile, character);
        diag.log("Saved slot " + string(_c.slot));
    });

    cmd.register("cmd_load_character", function(_c) {
        var data = save.load_slot(_c.slot);
        if (data == undefined) {
            diag.log("Load failed slot " + string(_c.slot));
            return;
        }
        if (is_struct(data.character)) {
            var ok = ports.snap.impl.apply_character(data.character);
            if (ok) {
                diag.log("Loaded slot " + string(_c.slot));
                sm.set(states.gameplay);
            } else {
                diag.log("Apply snapshot failed");
            }
        }
    });

    cmd.register("cmd_return_to_menu", function(_c) {
        sm.set(states.return_to_menu);
    });
	
	cmd.register("cmd_toggle_view", function(_c) {
	    view.mode = (view.mode == "iso") ? "ortho" : "iso";
	    eb.publish("ui:view_mode_changed", { mode: view.mode });
	    diag.log("View " + view.mode);
	});
	
	cmd.register("cmd_click_move", function(_c) {
	    // _c: { sx, sy, mode, cam, slot? }
	    var wpos;

	    if (_c.mode == "ortho") wpos = proj.screen_to_world_ortho(_c.sx, _c.sy, _c.cam);
	    else wpos = proj.screen_to_world_iso(_c.sx, _c.sy, _c.cam);

	    // tile coords in orthographic world pixels
	    var tx = floor(wpos.x / 32);
	    var ty = floor(wpos.y / 32);

	    // clamp to level bounds if available
	    // (domain owns level, but this is safe: read-only)
	    var lvl = domain.level;
	    if (is_struct(lvl)) {
	        tx = clamp(tx, 0, lvl.w - 1);
	        ty = clamp(ty, 0, lvl.h - 1);
	    }

	    // target center
	    var target_wx = tx * 32 + 16;
	    var target_wy = ty * 32 + 16;

	    // write into domain ONLY through IAction
	    ports.action.impl.set_move_target(target_wx, target_wy);

	    diag.log("Click tx " + string(tx) + " ty " + string(ty));
	});

    // World-affecting gameplay intents (Phase 5: all mutations originate from commands)
    cmd.register("cmd_pickup_item", function(_c) {
        // _c: { item_id }
        if (_c.item_id == undefined) return;
        ports.action.impl.player_try_pickup_item(_c.item_id);
    });

    cmd.register("cmd_attack_enemy", function(_c) {
        // _c: { enemy_id }
        if (_c.enemy_id == undefined) return;
        combat_player_issue_attack_order(domain, _c.enemy_id);
    });

    // Standard drop command: drop an item either at a world position (tile) or near the player.
    // _c: { name, mode:"near_player"|"world", sx, sy, cam, view_mode }
    cmd.register("cmd_drop_item_named", function(_c) {
        if (_c.name == undefined) return;

        var mode = _c.mode;
        if (mode == undefined) mode = "near_player";

        if (mode == "world") {
            // Translate GUI screen coords -> world -> tile center via ProjectionUtil.
            if (_c.sx == undefined || _c.sy == undefined || !is_struct(_c.cam)) {
                // Fallback to safe behavior.
                ports.action.impl.spawn_item_drop_near_player_named(_c.name);
                return;
            }

            var vm = _c.view_mode;
            if (vm == undefined) vm = view.mode;

            var wpos;
            if (vm == "ortho") wpos = proj.screen_to_world_ortho(_c.sx, _c.sy, _c.cam);
            else wpos = proj.screen_to_world_iso(_c.sx, _c.sy, _c.cam);

            ports.action.impl.spawn_item_drop_at_world_named(_c.name, wpos.x, wpos.y, true);
        } else {
            // Phase 4 behavior: ignore cursor, find nearest unoccupied tile to player.
            ports.action.impl.spawn_item_drop_near_player_named(_c.name);
        }
    });

	cmd.register("cmd_toggle_console", function(_c) {
	    var was_open = console.open;
	    console.toggle();
	    if (console.open) eb.publish("ui:console_opened", {});
	    else {
	        eb.publish("ui:console_closed", {});
	        // If the console was open and is now closed, latch capture for this frame
	        // so other systems (menu/gameplay) don't also consume Escape this frame.
		        if (was_open) set_frame_console_captured(true);
	    }
	});

	cmd.register("cmd_close_console", function(_c) {
	    if (console.open) {
	        // Latch capture for this frame even though console.open will become false.
		        set_frame_console_captured(true);
	        console.close();
	        eb.publish("ui:console_closed", {});
	    }
	});

	cmd.register("cmd_console_submit", function(_c) {
	    // _c.line
	    if (console.open) console.submit(_c.line);
	});

    cmd.register("cmd_give_item", function(_c) {
        // _c: { target, item, count }
        if (_c.target != "player") {
            console.print("Give failed: only target 'player' supported");
            return;
        }

        var item = _c.item;
        var count = _c.count;

        ports.action.impl.give_player_items(item, count);
        console.print("Gave player " + string(item) + " x" + string(count));
    });



	cmd.register("cmd_spawn_enemy", function(_c) {
	    diag.log("cmd_spawn_enemy received");
	    console.print("cmd_spawn_enemy received");

	    var tx = _c.tx;
	    var ty = _c.ty;

	    if (tx < 0 || ty < 0) {
	        console.print("Spawn failed: tx,ty must be >= 0");
	        return;
	    }

	    var lvl = domain.level;
	    if (is_struct(lvl)) {
	        if (tx >= lvl.w || ty >= lvl.h) {
	            console.print("Spawn failed: out of bounds");
	            return;
	        }
	    }

	    // spawn at tile center (visible marker)
	    var wx = tx * 32 + 16;
	    var wy = ty * 32 + 16;

	    // MUST exist on IAction impl:
	    ports.action.impl.spawn_enemy(wx, wy);

	    console.print("Spawned enemy at tile " + string(tx) + " " + string(ty));
	    diag.log("Spawned enemy tile " + string(tx) + " " + string(ty));
	});


    // Optional: log domain events
    eb.subscribe("domain:started", function(p) { diag.log("Domain started seed " + string(p.seed)); });
    eb.subscribe("domain:loaded", function(p) { diag.log("Domain loaded seed " + string(p.seed)); });
	eb.subscribe("ui:view_mode_changed", function(p) {
	    diag.log("View mode " + string(p.mode));
	});
	eb.subscribe("ui:console_opened", function(p) { diag.log("Console opened"); });
	eb.subscribe("ui:console_closed", function(p) { diag.log("Console closed"); });
	eb.subscribe("domain:enemy_spawned", function(p) {
	    diag.log("enemy_spawned id " + string(p.id));
	    console.print("enemy_spawned id " + string(p.id));
	});


    init = function() {
        cfg.load_all();
        assets.init();
        sm.set(states.menu);
    };

    // ------------------------------------------------------------
    // Phase 1: Single authoritative per-frame orchestrator
    // ------------------------------------------------------------
    // Order (must not change):
    //  1) input update
    //  2) console bridge (pending_* -> commands)
    //  3) domain invariants check (Phase 2 hook)
    //  4) command processing (state machine step)
    //  5) simulation step
    //  6) render packet build

    // Latched when a console-close action occurred (used to suppress gameplay/menu actions
    // in the same frame even if console.open becomes false before AppBoot.step runs).
    _console_capture_latch = false;

    // Guard: AppBoot.step may be called from more than one object (e.g. obj_boot and obj_game).
    // Prevent double simulation / double console-bridge in the same rendered frame.
    _last_step_frame_id = -1;

    // Kept as a public helper for other code paths (OR semantics).
    set_frame_console_captured = function(_v) {
        _console_capture_latch = (_console_capture_latch || _v);
    };

    _input_update = function() {
        // InputService is stateless today, but keep the phase to make ordering explicit.
        // Use dynamic lookup to avoid reading missing struct members.
        var fn = input[$ "update"];
        if (is_callable(fn)) { fn(); return; }
        fn = input[$ "step"];
        if (is_callable(fn)) { fn(); return; }
    };

    _console_bridge = function() {
        // AppBoot is the ONLY place that consumes pending_* requests.
        if (is_struct(console.pending_spawn)) {
            var req = console.pending_spawn;
            console.pending_spawn = undefined;

            diag.log("Bridge spawn tx=" + string(req.tx) + " ty=" + string(req.ty));
            console.print("Bridge dispatch cmd_spawn_enemy " + string(req.tx) + " " + string(req.ty));
            cmd.dispatch({ type: "cmd_spawn_enemy", tx: req.tx, ty: req.ty });
        }

        if (is_struct(console.pending_give)) {
            var req2 = console.pending_give;
            console.pending_give = undefined;

            diag.log("Bridge give target=" + string(req2.target) + " item=" + string(req2.item) + " count=" + string(req2.count));
            console.print("Bridge dispatch cmd_give_item " + string(req2.target) + " " + string(req2.item) + " " + string(req2.count));
            cmd.dispatch({ type: "cmd_give_item", target: req2.target, item: req2.item, count: req2.count });
        }
    };

    _domain_invariants_check = function() {
        // Phase 2 hook (no-op until implemented).
        var fn = domain[$ "invariants_check"];
        if (is_callable(fn)) fn();
    };

    _command_processing = function() {
        // No gameplay behavior should depend on console-open state except input capture.
        // If console is open OR we latched capture this frame, suppress state machine input.
        if (console.open || _console_capture_latch) return;
        sm.step();
    };

    _simulation_step = function(_dt) {
        // Only step when gameplay exists (level generated/loaded).
        if (!is_struct(domain.level)) return;
        ports.action.impl.step_simulation(_dt);
    };

    _render_packet_build = function() {
        // Safe even when level is undefined.
        domain.build_render_packets();
    };

    step = function() {
        // Frame-id derived from wall clock to be stable within a single engine frame.
        // (Avoids running twice if multiple instances call global.app.step in the same Step.)
        var _fps = max(1, room_speed);
        var _frame_id = floor(current_time / (1000 / _fps));
        if (_frame_id == _last_step_frame_id) return;
        _last_step_frame_id = _frame_id;

        var dt = 1 / room_speed;

        // 1) input update
        _input_update();
        time.step();

        // 2) console bridge
        _console_bridge();
        // 3) invariants
        _domain_invariants_check();
        // 4) command processing
        _command_processing();
        // 5) simulation
        _simulation_step(dt);
        // 6) render packets
        _render_packet_build();

        // Reset latch at end (if it was set after this step, it will be cleared next frame).
        _console_capture_latch = false;
    };



    draw = function() {
        sm.draw();
    };
}
