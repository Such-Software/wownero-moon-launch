extends Control
## Multi-page Help & Guide screen.
## Swipe-navigable pages covering all game mechanics.

const BS = preload("res://game/gui/ButtonStyles.gd")

const PAGE_TITLES: Array[String] = [
	"Controls",
	"Landing",
	"Fuel",
	"Crypto & Moonrocks",
	"Upgrades",
	"Weapons",
	"Hazards & Enemies",
	"Waypoints & Slingshots",
	"Difficulty",
	"Star Ratings & Scoring",
	"Leaderboard & Cloud Save",
	"Ship Skins",
]

var _current_page: int = 0
var _page_label: RichTextLabel = null
var _title_label: Label = null
var _page_counter: Label = null
var _prev_btn: Button = null
var _next_btn: Button = null

# Touch swipe tracking
var _swipe_start: Vector2 = Vector2.ZERO
var _swiping: bool = false
const SWIPE_THRESHOLD := 60.0


func _ready() -> void:
	_build_ui()
	_show_page(0)


func _build_ui() -> void:
	# Background — reuse starfield from scene
	# Title
	_title_label = Label.new()
	_title_label.name = "Title"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_title_label.offset_top = 16
	_title_label.offset_bottom = 56
	_title_label.add_theme_font_size_override("font_size", 30)
	_title_label.add_theme_color_override("font_color", Color.CYAN)
	if has_node("Label"):
		$Label.queue_free()
	add_child(_title_label)

	# Page counter "3 / 12"
	_page_counter = Label.new()
	_page_counter.name = "PageCounter"
	_page_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_counter.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_page_counter.offset_top = 50
	_page_counter.offset_bottom = 70
	_page_counter.add_theme_font_size_override("font_size", 14)
	_page_counter.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	add_child(_page_counter)

	# Scrollable content area
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 72
	scroll.offset_bottom = -60
	scroll.offset_left = 30
	scroll.offset_right = -30
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	_page_label = RichTextLabel.new()
	_page_label.name = "Content"
	_page_label.bbcode_enabled = true
	_page_label.fit_content = true
	_page_label.scroll_active = false
	_page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_label.custom_minimum_size = Vector2(964, 0)
	_page_label.add_theme_font_size_override("normal_font_size", 18)
	_page_label.add_theme_font_size_override("bold_font_size", 20)
	_page_label.add_theme_color_override("default_color", Color(0.85, 0.9, 0.95))
	scroll.add_child(_page_label)

	# Bottom bar with nav buttons
	var bottom := HBoxContainer.new()
	bottom.name = "BottomBar"
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -52
	bottom.offset_left = 20
	bottom.offset_right = -20
	bottom.add_theme_constant_override("separation", 12)
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(bottom)

	# Back to Menu
	var menu_btn := Button.new()
	menu_btn.text = "Menu"
	menu_btn.custom_minimum_size = Vector2(100, 38)
	menu_btn.add_theme_font_size_override("font_size", 16)
	BS.apply_space_style(menu_btn, Color.RED)
	menu_btn.pressed.connect(_on_menu_pressed)
	bottom.add_child(menu_btn)

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(spacer)

	# Prev
	_prev_btn = Button.new()
	_prev_btn.text = "< Prev"
	_prev_btn.custom_minimum_size = Vector2(110, 38)
	_prev_btn.add_theme_font_size_override("font_size", 16)
	BS.apply_space_style(_prev_btn, Color(0.5, 0.8, 1.0))
	_prev_btn.pressed.connect(_on_prev)
	bottom.add_child(_prev_btn)

	# Next
	_next_btn = Button.new()
	_next_btn.text = "Next >"
	_next_btn.custom_minimum_size = Vector2(110, 38)
	_next_btn.add_theme_font_size_override("font_size", 16)
	BS.apply_space_style(_next_btn, Color.GREEN)
	_next_btn.pressed.connect(_on_next)
	bottom.add_child(_next_btn)

	# Remove the old scene button if it exists
	if has_node("Button"):
		$Button.queue_free()


func _show_page(index: int) -> void:
	_current_page = clampi(index, 0, PAGE_TITLES.size() - 1)
	_title_label.text = PAGE_TITLES[_current_page]
	_page_counter.text = "%d / %d" % [_current_page + 1, PAGE_TITLES.size()]
	_page_label.text = _get_page_content(_current_page)
	_prev_btn.disabled = _current_page == 0
	_next_btn.disabled = _current_page == PAGE_TITLES.size() - 1
	# Reset scroll to top
	var scroll: ScrollContainer = get_node("Scroll")
	scroll.scroll_vertical = 0


func _on_prev() -> void:
	_show_page(_current_page - 1)

func _on_next() -> void:
	_show_page(_current_page + 1)

func _on_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://game/gui/menu/Menu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	# Keyboard navigation
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_LEFT:
				_on_prev()
				get_viewport().set_input_as_handled()
			KEY_RIGHT:
				_on_next()
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				_on_menu_pressed()
				get_viewport().set_input_as_handled()
	# Touch swipe
	if event is InputEventScreenTouch:
		if event.pressed:
			_swipe_start = event.position
			_swiping = true
		else:
			if _swiping:
				var delta: float = event.position.x - _swipe_start.x
				if delta < -SWIPE_THRESHOLD:
					_on_next()
				elif delta > SWIPE_THRESHOLD:
					_on_prev()
				_swiping = false


# ---------------------------------------------------------------------------
# Page content (BBCode)
# ---------------------------------------------------------------------------

func _get_page_content(page: int) -> String:
	match page:
		0: return _page_controls()
		1: return _page_landing()
		2: return _page_fuel()
		3: return _page_crypto()
		4: return _page_upgrades()
		5: return _page_weapons()
		6: return _page_hazards()
		7: return _page_waypoints()
		8: return _page_difficulty()
		9: return _page_scoring()
		10: return _page_leaderboard()
		11: return _page_skins()
	return ""


func _page_controls() -> String:
	return """[b]Keyboard Controls[/b]
[color=cyan]UP[/color] — Forward thrust
[color=cyan]DOWN[/color] — Reverse thrust
[color=cyan]LEFT / RIGHT[/color] — Rotate ship
[color=cyan]SPACE[/color] — Fire cannon (if purchased)
[color=cyan]M[/color] — Launch missile
[color=cyan]L[/color] — Laser beam (hold)
[color=cyan]E[/color] — EMP pulse
[color=cyan]F3[/color] — FPS/debug overlay
[color=cyan]ESC[/color] — Pause menu (in-game)

[b]Menu[/b]
Use the [color=cyan]Levels[/color] button to replay completed levels.

[b]Mobile Controls[/b]
[color=lime]Virtual Joystick[/color] — left side of screen, controls rotation
[color=lime]Thrust Buttons[/color] — right side, tap/hold for forward and reverse
[color=lime]Weapon Buttons[/color] — appear when weapons are purchased:
  [color=red]Crosshair[/color] — Cannon (auto-aim)
  [color=orange]M[/color] — Missile
  [color=aqua]L[/color] — Laser
  [color=dodgerblue]E[/color] — EMP

[b]Tips[/b]
Thrust uses fuel — let go when you have enough speed.
Rotate BEFORE thrusting to change direction efficiently.
Weapons are unlocked in the Upgrade Shop between levels."""


func _page_landing() -> String:
	return """[b]How to Land[/b]
Approach the target planet slowly and [color=lime]straight down[/color].
Your HUD shows landing speed — keep it [color=lime]green[/color].

[b]Speed Thresholds[/b]
[color=lime]Landing speed[/color] — safe touchdown (base 40 px/s)
[color=red]Crash speed[/color] — instant destruction (base 100 px/s)
Between them — you'll bounce or take damage.
Upgrades (Armor, Landing Gear) increase both thresholds.

[b]3D Landing Mode[/b]
Near a planet, a [color=yellow]3D chase camera[/color] activates automatically.
This shows your approach angle and altitude.

[color=cyan]ALT[/color] — altitude above surface
[color=cyan]SPD[/color] — descent speed (green=safe, yellow=caution, red=danger)
[color=cyan]Tilt Indicator[/color] — keep the bar centered!
[color=yellow]Arrows (<<<  >>>)[/color] — which way to correct

[b]Tilt Rules[/b]
[color=lime]< 18 deg[/color] — safe, no indicator
[color=yellow]18-35 deg[/color] — warning, correct NOW
[color=red]> 35 deg[/color] — too tilted, you WILL crash

[b]Landing Timer[/b]
Stay on the target for [color=cyan]3 seconds[/color] to plant your flag.
A countdown bar appears — hold steady!"""


func _page_fuel() -> String:
	return """[b]Fuel System[/b]
Every thrust burns fuel. No fuel = drift only (no thrust).

[b]Fuel Bar[/b]
Top of screen — shows remaining fuel as a colored bar.
[color=lime]Green[/color] — plenty of fuel
[color=yellow]Yellow[/color] — getting low
[color=red]Flashing RED + "LOW FUEL"[/color] — below 20%, conserve!

[b]Fuel Pickups[/b]
Floating [color=cyan]fuel canisters[/color] appear in levels.
Fly into them to restore [color=lime]25%[/color] of max fuel.
They're often placed near waypoint planets.

[b]Upgrades[/b]
[color=gold]Fuel Tank[/color] — increases maximum fuel capacity (+40/level)
[color=gold]Fuel Efficiency[/color] — reduces drain rate (-1.5/s per level)

[b]Tips[/b]
Coast when possible — fuel doesn't drain while drifting.
Waypoint planets give +10% fuel bonus on first visit.
The laser weapon also drains fuel (18/s) — use sparingly!"""


func _page_crypto() -> String:
	return """[b]Crypto & Moonrocks[/b]
Collect floating crypto coins during levels.
All crypto converts to [color=gold]Moonrocks[/color] on pickup.

[b]Crypto Types[/b]
[color=silver]WOW (Wownero)[/color] — common, worth 1 Moonrock
[color=green]DOGE[/color] — uncommon, worth 5 Moonrocks
[color=purple]XMR (Monero)[/color] — rare, purple glow, worth 10
[color=gold]BTC (Bitcoin)[/color] — very rare, golden glow, worth 50

[b]Spending Moonrocks[/b]
Between levels you visit the [color=cyan]Upgrade Shop[/color].
Buy upgrades, weapons, and ship skins with Moonrocks.

[b]Earning More[/b]
Complete levels to find crypto spawners.
Watch rewarded ads for [color=gold]+50 Moonrocks[/color].
Higher levels have more and rarer crypto.

[b]Crypto Magnet[/b]
Purchase the [color=gold]Magnet upgrade[/color] to auto-attract
nearby crypto pickups toward your ship."""


func _page_upgrades() -> String:
	return """[b]Upgrade Shop[/b]
After each level victory, spend Moonrocks on upgrades.
Each upgrade has [color=cyan]5 levels[/color] — cost increases per level.

[b]Ship Upgrades[/b]
[color=orange]Engine Power[/color] — more thrust force (+50/lvl)
[color=green]Fuel Tank[/color] — larger capacity (+40/lvl)
[color=cyan]Fuel Efficiency[/color] — less drain (-1.5/s per lvl)
[color=red]Armor Plating[/color] — survive harder impacts (+50/lvl)
[color=lime]Landing Gear[/color] — land at higher speed (+20/lvl)
[color=dodgerblue]Shield Generator[/color] — absorb 1 hit per level
[color=yellow]Gyroscope[/color] — faster rotation (+1000 torque/lvl)
[color=orange]Retro Rockets[/color] — stronger reverse thrust (+40/lvl)
[color=gold]Crypto Magnet[/color] — auto-attract crypto pickups

[b]Weapons[/b] (see Weapons page for details)
[color=red]Cannon[/color] — rapid-fire auto-aim gun
[color=orange]Missile[/color] — homing missiles (2 ammo/lvl)
[color=aqua]Laser[/color] — continuous beam (drains fuel)
[color=dodgerblue]EMP[/color] — area pulse (1 charge/lvl)

[b]Tips[/b]
Prioritize [color=lime]Landing Gear[/color] + [color=red]Armor[/color] early — they prevent crashes.
[color=green]Fuel Tank[/color] is essential for longer levels (5+).
Weapons aren't needed until enemies appear (Level 2+)."""


func _page_weapons() -> String:
	return """[b]Weapons[/b]
Purchase weapons in the Upgrade Shop. Each has 5 levels.

[b]Cannon[/b] [color=red](SPACE / Fire button)[/color]
Rapid-fire projectiles with [color=cyan]auto-aim[/color].
Targets nearest enemy within 300px and 70 deg cone.
Hold to fire continuously. Cooldown decreases per level.

[b]Missile Launcher[/b] [color=orange](M key / M button)[/color]
Fires [color=cyan]homing missiles[/color] that lock onto enemies.
Lock range: 500px, any direction. Turn rate: 3.5 rad/s.
Limited ammo: [color=yellow]2 missiles per upgrade level[/color] per run.

[b]Laser Beam[/b] [color=aqua](L key / L button)[/color]
Continuous beam — hold to fire.
Damages enemies on contact (0.15s tick rate).
[color=red]Warning:[/color] Drains 18 fuel/sec while active!
Range increases per level: 200 + 40 x level px.

[b]EMP Pulse[/b] [color=dodgerblue](E key / E button)[/color]
Destroys ALL enemies within radius.
Radius: 150 + 30 x level px.
Limited charges: [color=yellow]1 per upgrade level[/color] per run.
Causes screen shake + haptic feedback.

[b]Tips[/b]
Cannon is cheapest — buy it first for early levels.
Missiles are fire-and-forget — great for tough enemies.
Save EMP for emergencies when surrounded."""


func _page_hazards() -> String:
	return """[b]Hazards & Enemies[/b]

[color=red]Martians[/color] (Level 2+)
Alien ships that patrol and chase your rocket.
Contact is lethal (unless you have a shield).
Speed and count increase with level progression.

[color=yellow]Gamma Rays[/color] (Level 3+)
Directed energy projectiles fired at intervals.
The Mothership boss also fires aimed gamma rays.
Shields can absorb one hit.

[color=gray]Asteroids[/color] (Level 4+, orbiting Level 5+)
Drifting rocks — collision is fatal.
Orbiting asteroids circle planets at various speeds.
Count scales from 5 (Level 5) to 16 (Level 10).

[color=purple]Nebula Zones[/color] (Level 7+)
Glowing gas clouds that [color=red]drain fuel[/color] while inside.
Also apply gentle speed damping. Pass through quickly!

[color=cyan]Solar Wind[/color] (Level 6+)
Directional force zones that push your ship.
Visible as animated streak lines. Plan your approach!

[color=darkred]Black Holes[/color] (Level 9+)
Extreme gravity pull with inverse-distance falloff.
Instant death at the event horizon. Stay far away!
Some solar winds push you toward them — watch out!

[color=red]Martian Mothership[/color] (Level 11 Boss)
Massive 4x-scaled ship that patrols, spawns Martians,
and fires gamma rays. Land on its nose pad to win!"""


func _page_waypoints() -> String:
	return """[b]Waypoints & Checkpoints[/b] (Levels 5+)
Longer levels have intermediate planets as [color=cyan]waypoints[/color].
Enter a waypoint's gravity well to save your progress.

[b]Checkpoint System[/b]
When you visit a waypoint, your [color=lime]position, velocity,
and fuel[/color] are saved as a checkpoint.
If you die, the Death Screen offers:
  [color=green]"Retry from [Planet]"[/color] — resume from last checkpoint

Each waypoint gives [color=gold]+10% fuel bonus[/color] on first visit.

[b]Gravity Slingshot[/b]
Fly near any planet to use its gravity.
If your exit speed is [color=yellow]40+ px/s faster[/color] than entry:
  [color=gold]"SLINGSHOT!"[/color] — gold label with star burst
  Free speed boost — saves fuel!

[b]How to Slingshot[/b]
1. Approach a planet from the side (not head-on)
2. Let gravity curve your path around it
3. Thrust at the CLOSEST point for maximum boost
4. Exit trajectory should be toward your next target

[b]Wormholes[/b]
Swirling ring portals that [color=cyan]teleport[/color] your rocket.
Found in Levels 5, 8, and 10.
Brief cooldown after teleport prevents re-entry loops."""


func _page_difficulty() -> String:
	return """[b]Difficulty Settings[/b]
Toggle on the main menu — cycles Easy / Normal / Hard.

[b]Easy[/b] [color=lime](Green)[/color]
Enemy spawn intervals: x1.4 (slower spawns)
Enemy speed: x0.8 (slower enemies)
Fuel drain: x0.8 (less consumption)
Starting fuel: x1.2 (20% extra)
Crash speed: x1.3 (30% more forgiving)
Landing speed: x1.4 (40% more forgiving)

[b]Normal[/b] [color=gold](Gold)[/color]
All values at baseline — the intended experience.

[b]Hard[/b] [color=red](Red)[/color]
Enemy spawn intervals: x0.7 (faster spawns)
Enemy speed: x1.2 (faster enemies)
Fuel drain: x1.3 (more consumption)
Starting fuel: x0.9 (10% less)
Crash speed: x0.85 (15% stricter)
Landing speed: x0.8 (20% stricter)

[b]Tips[/b]
Start on Easy to learn the controls and level layouts.
Normal is balanced for players with a few upgrades.
Hard is a real challenge — max out upgrades first!
Difficulty is saved between sessions."""


func _page_scoring() -> String:
	return """[b]Star Ratings[/b]
Each level awards [color=gold]1-3 stars[/color] based on performance.

[b]How Stars Are Earned[/b]
[color=gold]3 Stars[/color] — finish under the target time
[color=silver]2 Stars[/color] — finish under 2x the target time
[color=gray]1 Star[/color] — just complete the level

[b]Fuel Bonus:[/b] Landing with 50%+ fuel remaining
bumps your star rating up by 1 (max 3).

[b]Target Times[/b]
Level 1 (Moon): 20s
Level 2 (Mars): 30s
Level 3 (Venus): 40s
Level 4 (Io): 50s
Level 5 (Jupiter): 60s
Level 6 (Saturn): 75s
Level 7 (Neptune): 90s
Level 8 (Pluto): 100s
Level 9 (Asteroids): 110s
Level 10 (Station): 120s
Level 11 (Mothership): 140s

[b]Best Records[/b]
Your best time and best star rating per level are saved.
Improving your time or stars updates the record.
Try to 3-star every level!"""


func _page_leaderboard() -> String:
	return """[b]Leaderboard[/b]
Your score is automatically submitted on each victory.
Rankings are per-level at [color=cyan]api.such.software[/color].

[b]What's Submitted[/b]
Level, time, fuel remaining, crypto collected, star rating.
Your pilot nickname and device ID identify you.

[b]Compete[/b]
Faster times rank higher. Compare with other players!
Change your [color=cyan]pilot nickname[/color] on the main menu
(Reroll for random, or Edit to type your own).

[b]Cloud Save[/b]
Your progress automatically backs up to the cloud.
If you reinstall or switch devices:
  [color=cyan]"Restore from Cloud"[/color] on the main menu
  downloads your saved progress.

Cloud restore keeps the [color=lime]better[/color] save — it won't
overwrite local progress if you're further ahead.

[b]What's Saved[/b]
Level progress, wallet, all upgrades, skins, best times,
star ratings, difficulty setting, and endless mode record."""


func _page_skins() -> String:
	return """[b]Ship Skins[/b]
Customize your rocket in the [color=cyan]Upgrade Shop[/color].
Scroll down past upgrades to find the skin gallery.

[b]Available Skins[/b]
[color=silver]Default[/color] — free, classic rocket
[color=orange]Retro[/color] — 200 Moonrocks
[color=gray]Stealth[/color] — 300 Moonrocks
[color=gold]Gold[/color] — 500 Moonrocks
[color=lime]Alien[/color] — 400 Moonrocks
[color=cyan]Wownero[/color] — 350 Moonrocks
[color=purple]Monero[/color] — 350 Moonrocks
[color=yellow]Bitcoin[/color] — 350 Moonrocks
[color=silver]Litecoin[/color] — 350 Moonrocks

[b]Achievement Skins[/b] [color=gold](Special)[/color]
[color=gold]Champion[/color] — earn 3 stars on ALL levels 1-11
[color=red]Skull[/color] — die 50 times total (wear it with pride!)
[color=aqua]Crystal Beetle[/color] — complete all 11 story levels
[color=silver]Steamboat[/color] — reach wave 10 in Endless Mode

These skins can't be purchased — only [color=cyan]earned[/color].
Once unlocked, select them in the shop skin gallery.

[b]How to Change Skins[/b]
Open the Upgrade Shop (after any level victory).
Scroll to the skin section at the bottom.
Tap a skin to buy or select it.
Your choice is saved automatically."""
