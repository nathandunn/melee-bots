class_name Hud
extends CanvasLayer
## All UI built in code: scoreboard, controls, team setup overlay, results overlay.
## Lays itself out for phone widths too (rows wrap, overlays shrink to the screen).

signal new_match_requested
signal batch_requested(n: int)
signal speed_changed(scale: float)
signal pause_toggled(paused: bool)

const PRESET_LIST := ["Balanced", "Brawler", "Slinger", "Coward", "Tactician", "Guardian", "Random", "Custom"]

var manager: MatchManager
var timer_label: Label
var team_labels: Array[Label] = []
var live_label: Label
var status_label: Label
var teams_overlay: Control
var teams_scroll: ScrollContainer
var results_overlay: Control
var results_scroll: ScrollContainer
var results_box: VBoxContainer
var results_title: Label
var results_countdown: Label
var next_row: HFlowContainer
var preset_buttons: Array[OptionButton] = []
var sliders := [{}, {}]
var slider_vals := [{}, {}]
var speed_buttons: Array[Button] = []
var teams_btn: Button
var live_btn: Button
var results_btn: Button
var last_result := {}
var _updating := false
var _tick := 0.0
var _root: Control


func setup(m: MatchManager) -> void:
	manager = m
	var theme := Theme.new()
	theme.default_font_size = 16
	_root = Control.new()
	_root.theme = theme
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(side, 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(vbox)

	# ---- row 1: clock + team status (wraps on phones)
	var row1 := HFlowContainer.new()
	row1.add_theme_constant_override("h_separation", 14)
	vbox.add_child(row1)
	timer_label = Label.new()
	timer_label.add_theme_font_size_override("font_size", 26)
	timer_label.text = "2:30"
	row1.add_child(timer_label)
	for t in 2:
		var l := Label.new()
		l.add_theme_color_override("font_color", MatchManager.TEAM_COLORS[t].lightened(0.2))
		l.add_theme_font_size_override("font_size", 19)
		row1.add_child(l)
		team_labels.append(l)

	# ---- row 2: controls (wraps on phones)
	var row2 := HFlowContainer.new()
	row2.add_theme_constant_override("h_separation", 6)
	vbox.add_child(row2)
	var pause_btn := Button.new()
	pause_btn.text = "Pause"
	pause_btn.toggle_mode = true
	pause_btn.toggled.connect(func(on: bool): pause_btn.text = "Play" if on else "Pause"; pause_toggled.emit(on))
	row2.add_child(pause_btn)
	for s in [1, 2, 4, 8]:
		var b := Button.new()
		b.text = "%dx" % s
		b.toggle_mode = true
		b.button_pressed = (s == 1)
		b.pressed.connect(func(): _set_speed(float(s)))
		row2.add_child(b)
		speed_buttons.append(b)
	teams_btn = Button.new()
	teams_btn.text = "Teams / setup"
	teams_btn.toggle_mode = true
	teams_btn.toggled.connect(func(on: bool): teams_overlay.visible = on; if on: results_overlay.visible = false)
	row2.add_child(teams_btn)
	live_btn = Button.new()
	live_btn.text = "Live list"
	live_btn.toggle_mode = true
	live_btn.toggled.connect(func(on: bool): live_label.visible = on)
	row2.add_child(live_btn)
	results_btn = Button.new()
	results_btn.text = "Last results"
	results_btn.disabled = true
	results_btn.pressed.connect(func(): if not last_result.is_empty(): show_result(last_result))
	row2.add_child(results_btn)
	var new_btn := Button.new()
	new_btn.text = "New match"
	new_btn.pressed.connect(func(): _close_overlays(); new_match_requested.emit())
	row2.add_child(new_btn)
	var batch_btn := Button.new()
	batch_btn.text = "Batch x10"
	batch_btn.pressed.connect(func(): _close_overlays(); batch_requested.emit(10))
	row2.add_child(batch_btn)

	# ---- live list (toggle)
	live_label = Label.new()
	live_label.add_theme_font_size_override("font_size", 13)
	live_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 0.9))
	live_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	live_label.visible = false
	vbox.add_child(live_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(spacer)

	# ---- bottom status line
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 14)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(status_label)

	_build_teams_overlay()
	_build_results_overlay()
	_refresh_sliders()
	get_tree().root.size_changed.connect(_relayout)
	_relayout()


# ---------------------------------------------------------------- overlays

func _overlay(title_text: String) -> Array:
	## Returns [overlay_control, scroll, content_vbox, title_label]
	var ov := Control.new()
	ov.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.visible = false
	_root.add_child(ov)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(center)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.12, 0.9)
	sb.border_color = Color(0.35, 0.38, 0.45)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	panel.add_child(outer)
	var head := HBoxContainer.new()
	outer.add_child(head)
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(title)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func(): ov.visible = false; teams_btn.set_pressed_no_signal(false))
	head.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	outer.add_child(scroll)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	return [ov, scroll, content, title]


func _build_teams_overlay() -> void:
	var parts := _overlay("Teams")
	teams_overlay = parts[0]
	teams_scroll = parts[1]
	var content: VBoxContainer = parts[2]
	var hint := Label.new()
	hint.text = "Pick a preset or drag the sliders, then Start match. Each robot gets the team personality with a little jitter."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 13)
	content.add_child(hint)
	var teams_row := HFlowContainer.new()
	teams_row.add_theme_constant_override("h_separation", 24)
	content.add_child(teams_row)
	for t in 2:
		teams_row.add_child(_build_team_panel(t))
	# the armoury: how many of each thing lie about the arena at the start
	var arm_title := Label.new()
	arm_title.text = "Armoury on the field"
	arm_title.add_theme_font_size_override("font_size", 18)
	content.add_child(arm_title)
	var arm_hint := Label.new()
	arm_hint.text = "Rocks are thrown (three sizes). Bats floor people, knives are quick, swords hit hardest, spears reach furthest (knives and spears can be thrown too). Get knocked down and you drop what you hold."
	arm_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	arm_hint.add_theme_font_size_override("font_size", 13)
	content.add_child(arm_hint)
	var arm_row := HFlowContainer.new()
	arm_row.add_theme_constant_override("h_separation", 16)
	content.add_child(arm_row)
	for k: String in ["rock", "bat", "knife", "sword", "spear"]:
		var cell := HBoxContainer.new()
		var kl := Label.new()
		kl.text = k.capitalize() + "s"
		cell.add_child(kl)
		var sb := SpinBox.new()
		sb.min_value = 0
		sb.max_value = 12
		sb.step = 1
		sb.value = int(manager.loadout.get(k, 0))
		var key: String = k
		sb.value_changed.connect(func(v: float): manager.loadout[key] = int(v))
		cell.add_child(sb)
		arm_row.add_child(cell)
	var start := Button.new()
	start.text = "Start match with these teams"
	start.add_theme_font_size_override("font_size", 18)
	start.pressed.connect(func(): _close_overlays(); new_match_requested.emit())
	content.add_child(start)


func _build_team_panel(t: int) -> Control:
	var box := VBoxContainer.new()
	var title := Label.new()
	title.text = MatchManager.TEAM_NAMES[t]
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", MatchManager.TEAM_COLORS[t].lightened(0.2))
	box.add_child(title)

	var ob := OptionButton.new()
	for p in PRESET_LIST:
		ob.add_item(p)
	ob.select(0)
	ob.item_selected.connect(func(idx: int): _on_preset(t, PRESET_LIST[idx]))
	box.add_child(ob)
	preset_buttons.append(ob)

	for trait_name in Personality.TRAITS:
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = trait_name
		l.custom_minimum_size.x = 84
		l.tooltip_text = Personality.TRAIT_HELP[trait_name]
		row.add_child(l)
		var s := HSlider.new()
		s.min_value = 0.0
		s.max_value = 1.0
		s.step = 0.05
		s.custom_minimum_size = Vector2(150, 28)
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		s.value_changed.connect(func(v: float): _on_slider(t, trait_name, v))
		row.add_child(s)
		var vl := Label.new()
		vl.custom_minimum_size.x = 36
		row.add_child(vl)
		box.add_child(row)
		sliders[t][trait_name] = s
		slider_vals[t][trait_name] = vl
	return box


func _build_results_overlay() -> void:
	var parts := _overlay("Results")
	results_overlay = parts[0]
	results_scroll = parts[1]
	results_box = parts[2]
	results_title = parts[3]
	# nothing starts by itself: the panel asks, you answer
	results_countdown = Label.new()
	results_countdown.add_theme_font_size_override("font_size", 13)
	results_countdown.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	next_row = HFlowContainer.new()
	next_row.add_theme_constant_override("h_separation", 10)
	next_row.add_theme_constant_override("v_separation", 6)
	var q := _cell("Start the next match?", true, Color.WHITE, 16)
	q.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	next_row.add_child(q)
	var same := Button.new()
	same.text = "Yes - same teams"
	same.pressed.connect(func(): _close_overlays(); new_match_requested.emit())
	next_row.add_child(same)
	var change := Button.new()
	change.text = "Change teams first"
	change.pressed.connect(func(): results_overlay.visible = false; teams_btn.button_pressed = true)
	next_row.add_child(change)
	var later := Button.new()
	later.text = "Not yet"
	later.pressed.connect(func(): results_overlay.visible = false; teams_btn.set_pressed_no_signal(false))
	next_row.add_child(later)


func on_match_started() -> void:
	results_overlay.visible = false
	set_countdown(0.0)


func _close_overlays() -> void:
	teams_overlay.visible = false
	results_overlay.visible = false
	teams_btn.set_pressed_no_signal(false)


func _relayout() -> void:
	var vs := get_viewport().get_visible_rect().size
	var w := vs.x
	var h := vs.y
	teams_scroll.custom_minimum_size = Vector2(minf(820.0, w - 40.0), minf(470.0, h - 110.0))
	# results share the screen with the celebration: right half in landscape, lower part in portrait
	var rc: Control = results_overlay.get_child(0)
	if w > h:
		rc.anchor_left = 0.5
		rc.anchor_top = 0.0
		rc.offset_left = 0.0
		rc.offset_top = 96.0  # below the button rows
		results_scroll.custom_minimum_size = Vector2(minf(620.0, w * 0.5 - 40.0), minf(560.0, h - 210.0))
	else:
		rc.anchor_left = 0.0
		rc.anchor_top = 0.42
		rc.offset_left = 0.0
		rc.offset_top = 0.0
		results_scroll.custom_minimum_size = Vector2(minf(900.0, w - 40.0), minf(600.0, h * 0.58 - 90.0))


# ---------------------------------------------------------------- team setup

func _on_preset(t: int, preset_name: String) -> void:
	if preset_name == "Custom":
		manager.team_preset_names[t] = "Custom"
		return
	manager.team_personalities[t] = Personality.preset(preset_name)
	manager.team_preset_names[t] = preset_name
	_refresh_sliders()


func _on_slider(t: int, trait_name: String, v: float) -> void:
	if _updating:
		return
	manager.team_personalities[t].set_trait(trait_name, v)
	slider_vals[t][trait_name].text = "%.2f" % v
	var lbl := manager.team_personalities[t].label()
	manager.team_preset_names[t] = lbl
	var idx := PRESET_LIST.find(lbl)
	preset_buttons[t].select(idx if idx >= 0 else PRESET_LIST.size() - 1)


func _refresh_sliders() -> void:
	_updating = true
	for t in 2:
		var p := manager.team_personalities[t]
		for trait_name in Personality.TRAITS:
			sliders[t][trait_name].value = p.get_trait(trait_name)
			slider_vals[t][trait_name].text = "%.2f" % p.get_trait(trait_name)
		var idx := PRESET_LIST.find(manager.team_preset_names[t])
		preset_buttons[t].select(idx if idx >= 0 else PRESET_LIST.size() - 1)
	_updating = false


func _set_speed(s: float) -> void:
	for b in speed_buttons:
		b.button_pressed = (b.text == "%dx" % int(s))
	speed_changed.emit(s)


# ---------------------------------------------------------------- live

func _process(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0 or manager == null:
		return
	_tick = 0.2
	var tl := manager.elapsed
	timer_label.text = "%d:%02d" % [int(tl) / 60, int(tl) % 60]
	for t in 2:
		team_labels[t].text = "%s %d/%d  HP %d%%" % [MatchManager.TEAM_NAMES[t], manager.alive_count(t), MatchManager.TEAM_SIZE,
			int(round(100.0 * manager.team_hp(t) / (Robot.MAX_HP * MatchManager.TEAM_SIZE)))]
	if live_label.visible:
		var lines := PackedStringArray()
		for r in manager.robots:
			var rk := (" [" + r.held.kind_name() + "]") if r.held != null else ""
			lines.append("%s %3d%% %s%s" % [r.robot_name, int(round(100.0 * r.hp / Robot.MAX_HP)), r.action, rk])
		live_label.text = "\n".join(lines)


func set_status(text: String) -> void:
	status_label.text = text


func set_countdown(_seconds: float) -> void:
	results_countdown.text = ""  # matches no longer start on a timer


# ---------------------------------------------------------------- results

func _clear_results() -> void:
	for c in results_box.get_children():
		results_box.remove_child(c)
		if c != results_countdown and c != next_row:
			c.queue_free()


func _cell(text: String, bold := false, color := Color.WHITE, size := 14) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_color_override("font_color", color.lightened(0.15))
	return l


static func _pct(hits: int, tries: int) -> String:
	return "%d%%" % int(round(100.0 * hits / tries)) if tries > 0 else "-"


func show_result(res: Dictionary) -> void:
	last_result = res
	results_btn.disabled = false
	_clear_results()
	teams_overlay.visible = false
	teams_btn.set_pressed_no_signal(false)
	var s: Dictionary = res["stats"]
	var wcol: Color = MatchManager.TEAM_COLORS[res["winner"]].lightened(0.25) if res["winner"] >= 0 else Color.WHITE
	results_title.text = "Match %d - %s wins by %s in %d s" % [res["match"], res["winner_name"], res["reason"], int(res["duration"])]
	results_title.add_theme_color_override("font_color", wcol)
	results_box.add_child(next_row)

	# team table
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 3)
	results_box.add_child(grid)
	grid.add_child(_cell(""))
	for t in 2:
		grid.add_child(_cell("%s (%s)" % [MatchManager.TEAM_NAMES[t], res["presets"][t]], true, MatchManager.TEAM_COLORS[t].lightened(0.2), 15))
	var rows := [
		["Alive", func(t): return "%d / %d" % [res["alive"][t], MatchManager.TEAM_SIZE]],
		["Team HP left", func(t): return "%d%%" % int(round(100.0 * res["hp"][t] / (Robot.MAX_HP * MatchManager.TEAM_SIZE)))],
		["Throws / hits", func(t): return "%d / %d  (%s)" % [s["throws"][t], s["rock_hits"][t], _pct(s["rock_hits"][t], s["throws"][t])]],
		["Punches / hits", func(t): return "%d / %d  (%s)" % [s["punches"][t], s["punch_hits"][t], _pct(s["punch_hits"][t], s["punches"][t])]],
		["Kicks / hits", func(t): return "%d / %d  (%s)" % [s["kicks"][t], s["kick_hits"][t], _pct(s["kick_hits"][t], s["kicks"][t])]],
		["Weapon swings / hits", func(t): return "%d / %d  (%s)" % [s["swings"][t], s["swing_hits"][t], _pct(s["swing_hits"][t], s["swings"][t])]],
		["Weapons dropped", func(t): return "%d" % s["drops"][t]],
		["Thrown damage", func(t): return "%d" % int(s["damage"][t]["rock"])],
		["Punch damage", func(t): return "%d" % int(s["damage"][t]["punch"])],
		["Kick damage", func(t): return "%d" % int(s["damage"][t].get("kick", 0.0))],
		["Weapon damage", func(t): return "%d" % int(s["damage"][t].get("melee", 0.0))],
		["Knockdowns dealt", func(t): return "%d" % s["knockdowns"][t]],
		["Kills (enemy dead)", func(t): return "%d" % s["kills"][t]],
		["Friendly-fire damage", func(t): return "%d" % int(s["friendly_fire"][t])],
		["Own goals (killed a mate)", func(t): return "%d" % int(s.get("own_goals", [0, 0])[t])],
	]
	for row in rows:
		grid.add_child(_cell(row[0], false, Color(0.8, 0.8, 0.85)))
		for t in 2:
			grid.add_child(_cell(row[1].call(t)))
	var hk: Array = s["hitbox_hist"].keys()
	hk.sort()
	var hparts := PackedStringArray()
	for k in hk:
		hparts.append("%s part%s: %d" % [str(k), "" if int(k) == 1 else "s", s["hitbox_hist"][k]])
	if hparts.size() > 0:
		results_box.add_child(_cell("Weapon hits by parts struck - " + ", ".join(hparts), false, Color(0.8, 0.8, 0.85), 13))

	# per-robot table
	results_box.add_child(_cell("Robots", true, Color.WHITE, 16))
	var rg := GridContainer.new()
	rg.columns = 13
	rg.add_theme_constant_override("h_separation", 14)
	rg.add_theme_constant_override("v_separation", 2)
	results_box.add_child(rg)
	for hdr in ["Robot", "Type", "Damage", "Thrown", "Punch", "Kick", "Weapon", "Throw acc", "Punch acc", "Kick acc", "Swing acc", "KD", "Kills / HP"]:
		rg.add_child(_cell(hdr, false, Color(0.75, 0.75, 0.8), 13))
	for r in res["robots"]:
		var col: Color = MatchManager.TEAM_COLORS[r["team"]].lightened(0.25)
		rg.add_child(_cell(r["name"], true, col))
		rg.add_child(_cell(r["preset"]))
		rg.add_child(_cell("%d" % int(r["dmg_rock"] + r["dmg_punch"] + r.get("dmg_kick", 0.0) + r.get("dmg_melee", 0.0))))
		rg.add_child(_cell("%d" % int(r["dmg_rock"])))
		rg.add_child(_cell("%d" % int(r["dmg_punch"])))
		rg.add_child(_cell("%d" % int(r.get("dmg_kick", 0.0))))
		rg.add_child(_cell("%d" % int(r.get("dmg_melee", 0.0))))
		rg.add_child(_cell("%d/%d %s" % [r["rock_hits"], r["throws"], _pct(r["rock_hits"], r["throws"])]))
		rg.add_child(_cell("%d/%d %s" % [r["punch_hits"], r["punches"], _pct(r["punch_hits"], r["punches"])]))
		rg.add_child(_cell("%d/%d %s" % [r.get("kick_hits", 0), r.get("kicks", 0), _pct(r.get("kick_hits", 0), r.get("kicks", 0))]))
		rg.add_child(_cell("%d/%d %s" % [r.get("swing_hits", 0), r.get("swings", 0), _pct(r.get("swing_hits", 0), r.get("swings", 0))]))
		rg.add_child(_cell("%d" % r["knockdowns"]))
		rg.add_child(_cell("%d / %s" % [r["kills"], ("%d%%" % int(round(100.0 * r["hp"] / Robot.MAX_HP))) if r["alive"] else "dead"]))

	results_overlay.visible = true
	results_scroll.scroll_vertical = 0
	set_status("Match over. Close the panel to watch; New match (or Teams / setup) when ready.")


func show_batch(summary: Dictionary) -> void:
	_clear_results()
	results_title.text = "Batch results"
	results_title.add_theme_color_override("font_color", Color.WHITE)
	results_box.add_child(next_row)
	var l := _cell(summary["text"])
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = minf(820.0, get_viewport().get_visible_rect().size.x - 70.0)
	results_box.add_child(l)
	results_overlay.visible = true
