# Headless check:  godot --headless --path . --script res://tests/test_links.gd
extends SceneTree

var fails := 0

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok: fails += 1

const A := "res://tests/fixtures/levels/a.tscn"
const B := "res://tests/fixtures/levels/b.tscn"

func _initialize() -> void:
	check(LinkChecker.entries_in(A) == PackedStringArray(["start"]), "entries_in lists entry names")
	check(LinkChecker.entries_in("res://tests/fixtures/levels/c.tscn").is_empty(), "missing level has no entries")
	var problems := LinkChecker.check(PackedStringArray([A, B]))
	for p in problems: print("      " + p)
	check(problems.size() == 3, "exactly three problems")
	check(problems.has("%s: Exit ToC → missing level res://tests/fixtures/levels/c.tscn" % B), "missing target level reported")
	check(problems.has("%s: Exit ToA → no entry 'nope' in %s" % [B, A]), "missing target entry reported")
	check(problems.has("%s: duplicate entry 'door'" % B), "duplicate entry reported")
	check(LinkChecker.check(PackedStringArray([A])).is_empty(), "a valid level has no problems")
	check(LinkChecker.find_levels("res://demo") == PackedStringArray(["res://demo/demo_room.tscn"]), "find_levels finds scenes holding a TerrainMap")
	check(LinkChecker.find_levels("res://tests/fixtures/levels").is_empty(), "scenes without a TerrainMap are not levels")
	print("FAILS: %d" % fails)
	quit(1 if fails else 0)
