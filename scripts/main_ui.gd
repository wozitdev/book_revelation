extends Control

@onready var text_display = $MarginContainer/VBoxContainer/ScrollContainer/VerseContainer/OriginalVerse
@onready var edited_text_display = $MarginContainer/VBoxContainer/ScrollContainer/VerseContainer/EditedVerse
@onready var chapter_verse_label = $MarginContainer/VBoxContainer/TopBar/HBoxContainer/ChapterVerseLabel
@onready var book = $Book
@onready var search_input = $MarginContainer/VBoxContainer/TopBar/SearchContainer/SearchBar/SearchInput
@onready var search_clear_button = $MarginContainer/VBoxContainer/TopBar/SearchContainer/SearchBar/SearchClearButton
@onready var search_results_container = $MarginContainer/VBoxContainer/TopBar/SearchContainer/SearchResultsContainer
@onready var search_results_list = $MarginContainer/VBoxContainer/TopBar/SearchContainer/SearchResultsContainer/SearchResultsList
@onready var toc_panel = $TOCDropdown
@onready var toc_container = $TOCDropdown/MarginContainer/VBoxContainer/ScrollContainer/TOCContainer
@onready var save_button = $MarginContainer/VBoxContainer/ButtonContainer/EditActions/SaveButton
@onready var changes_clear_button = $MarginContainer/VBoxContainer/ButtonContainer/EditActions/ChangesClearButton
@onready var toc_button = $MarginContainer/VBoxContainer/TopBar/HBoxContainer/TOCButton
@onready var previous_button = $MarginContainer/VBoxContainer/ButtonContainer/Navigation/PreviousButton
@onready var next_button = $MarginContainer/VBoxContainer/ButtonContainer/Navigation/NextButton

var verse_grids = {}  # Store verse grids by chapter for collapsing
var current_chapter_button = null
var current_verse_button = null
var edited_verses = {}
var search_timer: Timer
var last_search_text = ""
var session_data = {
	"last_position": {"chapter": 0, "verse": 0}
}

func _ready():
	await get_tree().process_frame
	
	if text_display and edited_text_display and chapter_verse_label and book:
		setup_export_button()
		setup_search_timer()
		
		# Load saved data
		load_session_data()
		load_edited_verses()
		
		# Setup TOC first
		if toc_container:
			setup_toc()
		
		# Navigate to saved position or default to Chapter 1, Verse 1
		book.navigate_to(session_data.last_position.chapter, session_data.last_position.verse)
		
		# Update display and TOC selection
		update_display()
		
		if search_results_container:
			search_results_container.hide()
		if toc_panel:
			toc_panel.hide()
		
		# Connect signals
		save_button.pressed.connect(_on_save_button_pressed)
		changes_clear_button.pressed.connect(_on_changes_clear_button_pressed)
		toc_button.pressed.connect(_on_toc_button_pressed)
		previous_button.pressed.connect(_on_previous_button_pressed)
		next_button.pressed.connect(_on_next_button_pressed)
		search_input.text_changed.connect(_on_search_input_text_changed)
		search_clear_button.pressed.connect(_on_clear_search_pressed)
		
		# Setup text editors
		text_display.editable = false
		text_display.add_theme_color_override("font_color", Color(1, 1, 1))
		text_display.context_menu_enabled = false
		
		edited_text_display.editable = true
		edited_text_display.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		edited_text_display.context_menu_enabled = false

func setup_search_timer():
	search_timer = Timer.new()
	search_timer.wait_time = 0.3
	search_timer.one_shot = true
	search_timer.timeout.connect(_perform_search)
	add_child(search_timer)

func setup_export_button():
	var edit_actions = $MarginContainer/VBoxContainer/ButtonContainer/EditActions
	var export_button = Button.new()
	export_button.text = "Export to File"
	export_button.custom_minimum_size = Vector2(120, 40)
	export_button.pressed.connect(_on_export_button_pressed)
	edit_actions.add_child(export_button)

func _on_export_button_pressed():
	var file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	file_dialog.current_file = "Revelation_edited.txt"
	file_dialog.add_filter("*.txt", "Text Files")
	
	add_child(file_dialog)
	file_dialog.file_selected.connect(_on_export_file_selected)
	file_dialog.popup_centered(Vector2i(800, 600))

func _on_export_file_selected(path: String):
	var original_file = FileAccess.open("res://Revelation.txt", FileAccess.READ)
	if not original_file:
		print("Error: Could not open original Revelation.txt file")
		return
	
	var content = original_file.get_as_text()
	original_file.close()
	
	# Process each edited verse in proper order
	var edited_keys = edited_verses.keys()
	
	# Sort by chapter and verse to ensure proper processing
	edited_keys.sort_custom(func(a, b):
		var parts_a = a.replace("Chapter ", "").replace("Verse ", "").split(", ")
		var parts_b = b.replace("Chapter ", "").replace("Verse ", "").split(", ")
		var ch_a = parts_a[0].to_int()
		var v_a = parts_a[1].to_int()
		var ch_b = parts_b[0].to_int()
		var v_b = parts_b[1].to_int()
		if ch_a != ch_b:
			return ch_a < ch_b
		return v_a < v_b
	)
	
	# Apply edits in reverse order to maintain correct positions
	edited_keys.reverse()
	
	for chapter_verse_key in edited_keys:
		var edited_text = edited_verses[chapter_verse_key]
		
		# Extract chapter and verse numbers from key
		var parts = chapter_verse_key.replace("Chapter ", "").replace("Verse ", "").split(", ")
		if parts.size() == 2:
			var chapter_num = parts[0].to_int()
			var verse_num = parts[1].to_int()
			
			# Format chapter and verse numbers with proper zero padding
			var verse_pattern = "66:%03d:%03d " % [chapter_num, verse_num]
			
			# Find start and end of this verse
			var start_pos = content.find(verse_pattern)
			if start_pos != -1:
				# Find the end of this verse
				var line_start = content.rfind("\n", start_pos)
				if line_start == -1:
					line_start = 0
				else:
					line_start += 1
				
				# Find next verse or chapter
				var next_verse_pattern = "66:%03d:%03d " % [chapter_num, verse_num + 1]
				var next_chapter_pattern = "66:%03d:001 " % [chapter_num + 1]
				
				var end_pos = content.length()
				var next_verse_pos = content.find(next_verse_pattern, start_pos)
				var next_chapter_pos = content.find(next_chapter_pattern, start_pos)
				
				if next_verse_pos != -1:
					end_pos = content.rfind("\n", next_verse_pos)
					if end_pos == -1:
						end_pos = next_verse_pos
				elif next_chapter_pos != -1:
					end_pos = content.rfind("\n", next_chapter_pos)
					if end_pos == -1:
						end_pos = next_chapter_pos
				
				# Replace the verse text while keeping the reference
				var replacement = verse_pattern + edited_text
				if end_pos < content.length():
					replacement += "\n"
				
				content = content.substr(0, line_start) + replacement + content.substr(end_pos + 1)
	
	# Write to export file
	var export_file = FileAccess.open(path, FileAccess.WRITE)
	if export_file:
		export_file.store_string(content)
		export_file.close()
		print("Export completed: " + path)
	else:
		print("Error: Could not create export file")

func load_session_data():
	var file = FileAccess.open("user://session_data.json", FileAccess.READ)
	if file:
		var data = JSON.parse_string(file.get_as_text())
		file.close()
		if data:
			session_data = data
		else:
			session_data = {
				"last_position": {"chapter": 0, "verse": 0},
			}
	else:
		session_data = {
			"last_position": {"chapter": 0, "verse": 0},
		}

func save_session_data():
	var file = FileAccess.open("user://session_data.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(session_data))
		file.close()

func _on_search_input_text_changed(text: String):
	search_timer.stop()
	last_search_text = text
	
	if text.length() < 2:
		search_results_container.hide()
		return
	
	search_timer.start()

func _on_clear_search_pressed():
	search_input.text = ""
	last_search_text = ""
	search_results_container.hide()

func _perform_search():
	if last_search_text.length() < 2:
		search_results_container.hide()
		return
	
	var results = book.search_including_edits(last_search_text, edited_verses)
	if results.size() > 0:
		# Sort results by chapter and verse
		results.sort_custom(func(a, b):
			if a["chapter"] != b["chapter"]:
				return a["chapter"] < b["chapter"]
			return a["verse"] < b["verse"]
		)
		display_search_results(results, last_search_text)
		search_results_container.show()
	else:
		search_results_container.hide()

func _on_search_result_clicked(chapter: int, verse: int):
	book.navigate_to(chapter, verse)
	session_data.last_position.chapter = chapter
	session_data.last_position.verse = verse
	save_session_data()
	
	update_display()
	update_toc_selection(chapter, verse)

func _on_previous_button_pressed():
	if book.previous_verse():
		session_data.last_position.chapter = book.current_chapter
		session_data.last_position.verse = book.current_verse
		save_session_data()
		
		update_display()
		update_toc_selection(book.current_chapter, book.current_verse)

func _on_next_button_pressed():
	if book.next_verse():
		session_data.last_position.chapter = book.current_chapter
		session_data.last_position.verse = book.current_verse
		save_session_data()
		
		update_display()
		update_toc_selection(book.current_chapter, book.current_verse)

func _on_verse_button_pressed(chapter: int, verse: int):
	if book.navigate_to(chapter, verse):
		session_data.last_position.chapter = chapter
		session_data.last_position.verse = verse
		save_session_data()
		
		update_display()
		update_toc_selection(chapter, verse)

func setup_toc():
	for child in toc_container.get_children():
		child.queue_free()
	
	var toc_data = book.get_toc_data()
	for entry in toc_data:
		var chapter_section = VBoxContainer.new()
		var chapter_header = Button.new()
		
		# Check if any verses in this chapter have been edited
		var has_edits = false
		for verse in range(entry["verse_count"]):
			var check_key = "Chapter %d, Verse %d" % [entry["chapter"], verse + 1]
			if edited_verses.has(check_key):
				has_edits = true
				break
		
		# Add visual indicator for edited chapters
		var chapter_text = "Chapter %d: %s" % [entry["chapter"], entry["title"]]
		if has_edits:
			chapter_text += "*"
		chapter_header.text = chapter_text
		
		chapter_header.add_theme_font_size_override("font_size", 16)
		chapter_header.flat = true
		chapter_header.alignment = HORIZONTAL_ALIGNMENT_LEFT
		chapter_header.custom_minimum_size.x = 500
		
		# Color edited chapters differently
		if has_edits:
			chapter_header.add_theme_color_override("font_color", Color(1.0, 0.8, 0.6))
		
		# Highlight if this is the current chapter
		if entry["chapter"] - 1 == book.current_chapter:
			chapter_header.add_theme_color_override("font_color", Color(0.3, 0.7, 1.0))
		
		var verse_grid = GridContainer.new()
		verse_grid.columns = 10
		verse_grid.visible = false
		verse_grids[entry["chapter"] - 1] = verse_grid
		
		chapter_section.add_child(chapter_header)
		chapter_section.add_child(verse_grid)
		
		chapter_header.pressed.connect(_on_chapter_header_pressed.bind(entry["chapter"] - 1))
		
		for verse in range(entry["verse_count"]):
			var verse_button = Button.new()
			var verse_key = "Chapter %d, Verse %d" % [entry["chapter"], verse + 1]
			
			# Add visual indicator for edited verses
			if edited_verses.has(verse_key):
				verse_button.text = str(verse + 1) + "*"
				verse_button.add_theme_color_override("font_color", Color(1.0, 0.8, 0.6))
			else:
				verse_button.text = str(verse + 1)
			
			verse_button.custom_minimum_size = Vector2(30, 30)
			verse_button.pressed.connect(_on_verse_button_pressed.bind(entry["chapter"] - 1, verse))
			
			# Highlight current verse
			if entry["chapter"] - 1 == book.current_chapter and verse == book.current_verse:
				verse_button.add_theme_color_override("font_color", Color(0.3, 0.7, 1.0))
			
			verse_grid.add_child(verse_button)
		
		toc_container.add_child(chapter_section)
		
		# Expand current chapter
		if entry["chapter"] - 1 == book.current_chapter:
			verse_grid.visible = true

func _on_chapter_header_pressed(chapter: int):
	# Prevent collapsing the currently selected chapter
	if chapter == book.current_chapter:
		return
	
	var verse_grid = verse_grids[chapter]
	verse_grid.visible = !verse_grid.visible

func update_display():
	var current_text = book.get_current_text()
	text_display.text = current_text
	
	var chapter_verse = book.get_chapter_verse()
	var saved_edit = load_edit(chapter_verse)
	edited_text_display.text = saved_edit if saved_edit else current_text
	
	chapter_verse_label.text = chapter_verse
	update_toc_selection(book.current_chapter, book.current_verse)
	
	# Clear edit indicators when changing verses
	update_toc_edit_indicators()

func update_toc_edit_indicators():
	# Refresh the TOC to update edit indicators
	setup_toc()

func _on_save_button_pressed():
	var chapter_verse = book.get_chapter_verse()
	var original_text = text_display.text
	var edited_text = edited_text_display.text
	
	# Don't save if text hasn't changed
	if original_text == edited_text:
		print("No changes to save for " + chapter_verse)
		return
	
	save_edit(chapter_verse, edited_text)
	# Update TOC to show new edit indicator
	update_toc_edit_indicators()

func _on_changes_clear_button_pressed():
	edited_text_display.text = text_display.text
	var chapter_verse = book.get_chapter_verse()
	clear_edit(chapter_verse)
	# Update TOC to remove edit indicator
	update_toc_edit_indicators()

func save_edit(chapter_verse: String, text: String):
	var save_data = {}
	
	# Load existing saves first
	var read_file = FileAccess.open("user://edited_verses.json", FileAccess.READ)
	if read_file:
		var data = JSON.parse_string(read_file.get_as_text())
		if data:
			save_data = data
		read_file.close()
	
	# Update with new edit
	save_data[chapter_verse] = text
	
	# Update local copy
	edited_verses[chapter_verse] = text
	
	# Save back to file
	var write_file = FileAccess.open("user://edited_verses.json", FileAccess.WRITE)
	if write_file:
		write_file.store_string(JSON.stringify(save_data))
		write_file.close()
		print("Saved edit for " + chapter_verse)
	else:
		print("Error: Could not save edit")

func load_edit(chapter_verse: String) -> String:
	var read_file = FileAccess.open("user://edited_verses.json", FileAccess.READ)
	if read_file:
		var data = JSON.parse_string(read_file.get_as_text())
		read_file.close()
		if data and data.has(chapter_verse):
			return data[chapter_verse]
	return ""

func clear_edit(chapter_verse: String):
	var save_data = {}
	
	# Load existing saves first
	var read_file = FileAccess.open("user://edited_verses.json", FileAccess.READ)
	if read_file:
		var data = JSON.parse_string(read_file.get_as_text())
		if data:
			save_data = data
		read_file.close()
	
	# Remove the edit if it exists
	if save_data.has(chapter_verse):
		save_data.erase(chapter_verse)
		
		# Update local copy
		if edited_verses.has(chapter_verse):
			edited_verses.erase(chapter_verse)
		
		# Save back to file
		var write_file = FileAccess.open("user://edited_verses.json", FileAccess.WRITE)
		if write_file:
			write_file.store_string(JSON.stringify(save_data))
			write_file.close()
			print("Cleared edit for " + chapter_verse)
		else:
			print("Error: Could not save after clearing edit")

func _on_toc_button_pressed():
	toc_panel.visible = !toc_panel.visible

func load_edited_verses():
	var read_file = FileAccess.open("user://edited_verses.json", FileAccess.READ)
	if read_file:
		var data = JSON.parse_string(read_file.get_as_text())
		read_file.close()
		if data:
			edited_verses = data
		else:
			edited_verses = {}
	else:
		edited_verses = {}

func display_search_results(results: Array, search_text: String):
	# Clear previous results
	for child in search_results_list.get_children():
		child.queue_free()
	
	for result in results:
		var result_container = VBoxContainer.new()
		result_container.add_theme_constant_override("separation", 5)
		
		# Create clickable header
		var header_button = Button.new()
		header_button.text = "Chapter %d, Verse %d" % [result["chapter"] + 1, result["verse"] + 1]
		header_button.flat = true
		header_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		header_button.add_theme_font_size_override("font_size", 14)
		header_button.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
		
		# Create preview with highlighted search terms
		var preview_label = RichTextLabel.new()
		preview_label.bbcode_enabled = true
		preview_label.fit_content = true
		preview_label.scroll_active = false
		
		var highlighted_text = highlight_search_terms(result["preview"], search_text)
		preview_label.text = highlighted_text
		
		# Connect click handler
		header_button.pressed.connect(_on_search_result_clicked.bind(result["chapter"], result["verse"]))
		
		result_container.add_child(header_button)
		result_container.add_child(preview_label)
		
		# Add separator
		var separator = HSeparator.new()
		result_container.add_child(separator)
		
		search_results_list.add_child(result_container)

func highlight_search_terms(text: String, search_terms: String) -> String:
	var words = search_terms.to_lower().split(" ")
	var highlighted = text
	
	for word in words:
		if word.length() >= 2:
			# Use case-insensitive replacement with BBCode highlighting
			var regex = RegEx.new()
			regex.compile("(?i)\\b" + word + "\\b")
			highlighted = regex.sub(highlighted, "[bgcolor=#ffff00][color=#000000]$0[/color][/bgcolor]", true)
	
	return highlighted

func update_toc_selection(chapter: int, verse: int):
	# Reset previous verse selection only
	if current_verse_button:
		current_verse_button.modulate = Color(1, 1, 1)
		if current_verse_button.has_theme_color_override("font_color"):
			current_verse_button.remove_theme_color_override("font_color")
	
	# Update current selections
	if chapter < toc_container.get_child_count():
		var chapter_section = toc_container.get_child(chapter)
		if chapter_section:
			current_chapter_button = chapter_section.get_child(0)  # Chapter header button
			
			# Check if this chapter has edits (preserve the edit indicator color)
			var has_edits = false
			for v in range(book.chapters[chapter].size()):
				var check_key = "Chapter %d, Verse %d" % [chapter + 1, v + 1]
				if edited_verses.has(check_key):
					has_edits = true
					break
			
			if has_edits:
				current_chapter_button.add_theme_color_override("font_color", Color(1.0, 0.8, 0.6))
			else:
				current_chapter_button.add_theme_color_override("font_color", Color(0.3, 0.7, 1.0))
			
			var verse_grid = verse_grids[chapter]
			if verse >= 0 and verse_grid and verse < verse_grid.get_child_count():
				current_verse_button = verse_grid.get_child(verse)
				current_verse_button.add_theme_color_override("font_color", Color(0.3, 0.7, 1.0))
				
				# Ensure current chapter is expanded
				if not verse_grid.visible:
					verse_grid.visible = true