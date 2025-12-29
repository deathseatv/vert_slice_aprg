function AppBoot() constructor {
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

	cmd.register("cmd_toggle_console", function(_c) {
	    console.toggle();
	    if (console.open) eb.publish("ui:console_opened", {});
	    else eb.publish("ui:console_closed", {});
	});

	cmd.register("cmd_close_console", function(_c) {
	    if (console.open) {
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

	step = function() {
	    time.step();
	    sm.step();

	    // Console -> Command bridge
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



    draw = function() {
        sm.draw();
    };
}
