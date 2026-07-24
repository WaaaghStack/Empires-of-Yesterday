extends SceneTree
## Structural gate for docs/AUDIT_CELL_WORLD_BUGS_UX.md (list-only audit deliverable).
## Run: godot --headless --path . -s res://tools/verify_audit_cell_world_doc.gd

const AUDIT_PATH := "res://docs/AUDIT_CELL_WORLD_BUGS_UX.md"


func _initialize() -> void:
	var abs_path: String = ProjectSettings.globalize_path(AUDIT_PATH)
	if not FileAccess.file_exists(AUDIT_PATH):
		push_error("FAIL missing %s" % AUDIT_PATH)
		quit(1)
		return
	var text: String = FileAccess.get_file_as_string(AUDIT_PATH)
	if text.strip_edges().is_empty():
		push_error("FAIL audit file empty")
		quit(1)
		return
	var fails: PackedStringArray = PackedStringArray()
	if text.find("no product code was changed") < 0:
		fails.append("missing no-product-code stage statement")
	if text.find("Prioritized fix order") < 0 and text.find("Suggested next implementation") < 0:
		fails.append("missing prioritization section")
	if text.find("**Category**") < 0:
		fails.append("missing Category fields")
	if text.find("**Severity**") < 0:
		fails.append("missing Severity fields")
	if text.find("**Anchors**") < 0:
		fails.append("missing Anchors fields")
	if text.find("sphere") < 0 and text.find("cell_index") < 0:
		fails.append("missing cell/sphere coverage")
	if text.find("SCD1") < 0:
		fails.append("missing SCD1 coverage")
	if text.find("BFS") < 0 and text.find("occupan") < 0:
		fails.append("missing pathing/occupancy coverage")
	var heading_re := RegEx.new()
	heading_re.compile("(?m)^### [A-E]\\d+")
	var matches: Array = heading_re.search_all(text)
	if matches.size() < 10:
		fails.append("too few discrete findings (%d)" % matches.size())
	if not fails.is_empty():
		for f in fails:
			push_error("FAIL %s" % f)
		quit(1)
		return
	print("PASS audit doc %s findings=%d path=%s" % [AUDIT_PATH, matches.size(), abs_path])
	quit(0)
