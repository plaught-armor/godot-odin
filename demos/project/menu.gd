extends Control
## Opens each demo. Every demo runs one algorithm twice, in Odin and in GDScript, from the same
## seed, and Tab switches between them so the readout compares like with like.

var _demos: PackedStringArray = [
	"Boids swarm",
	"res://boids/boids.tscn",
	"Thousands of boids, each steering by every neighbour in its grid cells. Float math in a tight loop.",
	"Falling sand",
	"res://sand/sand.tscn",
	"130 000 cells of sand, water and wall, every cell updated every frame. Byte arrays.",
	"Pathfinding swarm",
	"res://flow/flow.tscn",
	"Dijkstra flow field over 37 000 cells, rebuilt as you drag the target; units walk it.",
	"Procedural terrain",
	"res://terrain/terrain.tscn",
	"Fractal Perlin noise, normals and colours for a mesh of up to 262 000 vertices.",
]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 14)
	center.add_child(column)
	var title: Label = Label.new()
	title.text = "godot-odin demos: Odin against GDScript"
	title.add_theme_font_size_override(&"font_size", 28)
	column.add_child(title)
	for d: int in range(0, _demos.size(), 3):
		var button: Button = Button.new()
		button.text = _demos[d]
		button.custom_minimum_size = Vector2(560.0, 44.0)
		button.pressed.connect(_open.bind(_demos[d + 1]))
		column.add_child(button)
		var about: Label = Label.new()
		about.text = _demos[d + 2]
		about.modulate = Color(0.75, 0.75, 0.8)
		column.add_child(about)
		if d == 0:
			button.grab_focus.call_deferred()
	var hint: Label = Label.new()
	hint.text = "In a demo: Tab switches Odin/GDScript, R resets, Esc comes back here. Esc here quits."
	column.add_child(hint)


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_ESCAPE:
		get_tree().quit()


func _open(scene: String) -> void:
	get_tree().change_scene_to_file(scene)
