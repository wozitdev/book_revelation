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
@onready var pages_button = $MarginContainer/VBoxContainer/TopBar/HBoxContainer/PagesButton
@onready var pages_panel = $PagesPanel
@onready var pages_content = $PagesPanel/MarginContainer/VBoxContainer/ScrollContainer/PagesContent
@onready var pages_close_button = $PagesPanel/MarginContainer/VBoxContainer/Header/CloseButton
@onready var sticky_chapter_label = $PagesPanel/MarginContainer/VBoxContainer/Header/StickyChapterLabel
@onready var previous_button = $MarginContainer/VBoxContainer/ButtonContainer/Navigation/PreviousButton
@onready var next_button = $MarginContainer/VBoxContainer/ButtonContainer/Navigation/NextButton

var verse_grids = {}  # Store verse grids by chapter for collapsing
var chapter_containers = []  # Store chapter containers for scroll tracking
var current_chapter_button = null
var current_verse_button = null
var edited_verses = {}
var search_timer: Timer
var last_search_text = ""
var pages_scroll_container: ScrollContainer

# Lazy loading variables
var pages_data_cached = false
var pages_chapter_data = []  # Pre-computed chapter data for faster rendering

var session_data = {
	"last_position": {"chapter": 1, "verse": 0},  # chapter is 1-based, verse is 0-based
	"expanded_chapters": {},  # Will be populated with proper keys
	"pages_scroll_position": 0  # Scroll position in pages view
}

func _ready():
	await get_tree().process_frame
	
	if text_display and edited_text_display and chapter_verse_label and book:
		setup_search_timer()
		load_session_data()
		load_edited_verses()
		
		# Setup TOC after loading session data
		if toc_container:
			setup_toc()
		
		# Navigate to saved position or default to Chapter 1, Verse 1
		# session_data: chapter is 1-based, verse is 0-based
		# navigate_to expects: chapter (1-based), verse (1-based)
		if not book.navigate_to(session_data.last_position.chapter, session_data.last_position.verse + 1):
			# If navigation fails, reset to first verse (Chapter 1, Verse 1)
			session_data.last_position.chapter = 1
			session_data.last_position.verse = 0
			book.navigate_to(1, 1)
			save_session_data()
		
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
		pages_button.pressed.connect(_on_pages_button_pressed)
		pages_close_button.pressed.connect(_on_pages_close_pressed)
		previous_button.pressed.connect(_on_previous_button_pressed)
		next_button.pressed.connect(_on_next_button_pressed)
		search_input.text_changed.connect(_on_search_input_text_changed)
		search_clear_button.pressed.connect(_on_clear_search_pressed)
		
		# Setup text editors
		text_display.editable = false
		text_display.add_theme_color_override("font_color", Color(1, 1, 1))
		
		edited_text_display.editable = true
		edited_text_display.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		
		# Get scroll container reference and populate pages on launch
		pages_scroll_container = $PagesPanel/MarginContainer/VBoxContainer/ScrollContainer
		await populate_pages_view()
		
		# Initialize sticky label to chapter 1
		sticky_chapter_label.text = "Chapter 1: %s" % book.chapter_titles[0] if book.chapter_titles.size() > 0 else "Chapter 1"
		
		# Connect scroll signal for sticky chapter header
		pages_scroll_container.get_v_scroll_bar().value_changed.connect(_on_pages_scroll)
		
		# Restore scroll position after a frame
		await get_tree().process_frame
		if pages_scroll_container:
			pages_scroll_container.scroll_vertical = session_data.pages_scroll_position
			# Only update if we've scrolled (not at position 0)
			if session_data.pages_scroll_position > 0:
				_update_sticky_chapter_label()

func _on_pages_scroll(_value: float):
	_update_sticky_chapter_label()

func _update_sticky_chapter_label():
	if not pages_scroll_container or chapter_containers.size() == 0:
		return
	
	var scroll_pos = pages_scroll_container.scroll_vertical
	var current_chapter_idx = 0
	
	# Find which chapter is at the top of the scroll view
	for i in range(chapter_containers.size()):
		var container = chapter_containers[i]
		# Check if container is still valid (not freed)
		if not is_instance_valid(container):
			return
		if container.position.y <= scroll_pos + 50:  # 50px tolerance
			current_chapter_idx = i
	
	# Update sticky label and pages title
	var chapter_num = current_chapter_idx + 1
	var chapter_title = book.chapter_titles[current_chapter_idx] if current_chapter_idx < book.chapter_titles.size() else ""
	sticky_chapter_label.text = "Chapter %d: %s" % [chapter_num, chapter_title]

func _unhandled_input(event):
	if event is InputEventKey and event.pressed:
		if event.ctrl_pressed and event.keycode == KEY_S:
			_on_save_button_pressed()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			# Close pages panel or TOC on Escape
			if pages_panel.visible:
				_save_pages_scroll_position()
				pages_panel.visible = false
				get_viewport().set_input_as_handled()
			elif toc_panel.visible:
				toc_panel.visible = false
				get_viewport().set_input_as_handled()

func setup_search_timer():
	search_timer = Timer.new()
	search_timer.wait_time = 0.3
	search_timer.one_shot = true
	search_timer.timeout.connect(_perform_search)
	add_child(search_timer)

func load_session_data():
	# Initialize with default values first (chapter is 1-based, verse is 0-based)
	session_data = {
		"last_position": {"chapter": 1, "verse": 0},
		"expanded_chapters": {},
		"pages_scroll_position": 0
	}
	
	var data = null
	
	# Web-compatible loading
	if OS.has_feature("web"):
		# Use JavaScript localStorage for web builds
		var json_string = _web_storage_get("revelation_session_data")
		if json_string != "":
			data = JSON.parse_string(json_string)
	else:
		# Use normal file system for desktop
		var file = FileAccess.open("user://session_data.json", FileAccess.READ)
		if file:
			data = JSON.parse_string(file.get_as_text())
			file.close()
	
	if data:
		# Load last position
		if data.has("last_position"):
			session_data.last_position = data.last_position
		
		# Load expanded chapters
		if data.has("expanded_chapters"):
			for key in data.expanded_chapters:
				var chapter_index = int(key) if key is String else key
				session_data.expanded_chapters[chapter_index] = data.expanded_chapters[key]
		
		# Load pages scroll position
		if data.has("pages_scroll_position"):
			session_data.pages_scroll_position = int(data.pages_scroll_position)

func save_session_data():
	# Convert integer keys to strings for JSON compatibility
	var save_data = {
		"last_position": session_data.last_position,
		"expanded_chapters": {},
		"pages_scroll_position": session_data.pages_scroll_position
	}
	
	for chapter_index in session_data.expanded_chapters:
		save_data.expanded_chapters[str(chapter_index)] = session_data.expanded_chapters[chapter_index]
	
	# Web-compatible saving
	if OS.has_feature("web"):
		# Use JavaScript localStorage for web builds with proper escaping
		var json_string = JSON.stringify(save_data)
		_web_storage_set("revelation_session_data", json_string)
	else:
		# Use normal file system for desktop
		var file = FileAccess.open("user://session_data.json", FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(save_data))
			file.close()

# Helper functions for web storage with proper escaping
func _web_storage_set(key: String, value: String):
	# Use encodeURIComponent for safe storage of special characters
	var encoded_value = value.uri_encode()
	var js_code = "(function(){try{localStorage.setItem('%s',decodeURIComponent('%s'));return true;}catch(e){console.error('Storage error:',e);return false;}})();" % [key, encoded_value]
	JavaScriptBridge.eval(js_code)

func _web_storage_get(key: String) -> String:
	var js_code = "(function(){var val=localStorage.getItem('%s');return val!==null?encodeURIComponent(val):null;})();" % [key]
	var result = JavaScriptBridge.eval(js_code)
	if result != null and str(result) != "null" and str(result) != "":
		return str(result).uri_decode()
	return ""

func _on_search_input_text_changed(text: String):
	search_timer.stop()
	last_search_text = text
	
	if text.length() < 2:
		search_results_container.hide()
		clear_search_highlighting()
		return
	
	search_timer.start()

func _on_clear_search_pressed():
	search_input.text = ""
	last_search_text = ""
	search_results_container.hide()
	clear_search_highlighting()

func _perform_search():
	if last_search_text.length() < 2:
		search_results_container.hide()
		clear_search_highlighting()
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
		apply_search_highlighting()
	else:
		search_results_container.hide()
		clear_search_highlighting()

func _on_search_result_clicked(chapter: int, verse: int):
	# chapter and verse from search results are 1-based
	if book.navigate_to(chapter, verse):
		# Save using book's current state for consistency (chapter is 1-based, verse is 0-based)
		session_data.last_position.chapter = book.current_chapter
		session_data.last_position.verse = book.current_verse
		save_session_data()
		
		update_display()
		update_toc_selection(book.current_chapter, book.current_verse)
		apply_search_highlighting()

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
	# chapter and verse are 0-based from the TOC, convert to 1-based for navigate_to
	if book.navigate_to(chapter + 1, verse + 1):
		# Save using book's current state for consistency (chapter is 1-based, verse is 0-based)
		session_data.last_position.chapter = book.current_chapter
		session_data.last_position.verse = book.current_verse
		save_session_data()
		
		update_display()
		update_toc_selection(book.current_chapter, book.current_verse)

func _on_toc_button_pressed():
	toc_panel.visible = !toc_panel.visible
	# Hide pages panel if opening TOC
	if toc_panel.visible:
		_save_pages_scroll_position()
		pages_panel.visible = false

func _on_pages_button_pressed():
	# Hide TOC when opening pages
	toc_panel.visible = false
	pages_panel.visible = true
	# Refresh pages view to show any newly edited verses
	await populate_pages_view()
	# Restore scroll position after showing
	await get_tree().process_frame
	if pages_scroll_container:
		pages_scroll_container.scroll_vertical = session_data.pages_scroll_position

func _on_pages_close_pressed():
	_save_pages_scroll_position()
	pages_panel.visible = false

func _save_pages_scroll_position():
	if pages_scroll_container:
		session_data.pages_scroll_position = pages_scroll_container.scroll_vertical
		save_session_data()

func populate_pages_view():
	# Use cached data if available and not stale
	if not pages_data_cached:
		_prepare_pages_data()
	
	# Clear existing content
	for child in pages_content.get_children():
		child.queue_free()
	
	# Wait for nodes to be freed
	await get_tree().process_frame
	
	# Clear chapter containers tracking
	chapter_containers.clear()
	
	# Render all chapters with pre-computed data
	for chapter_data in pages_chapter_data:
		var chapter_container = VBoxContainer.new()
		chapter_container.add_theme_constant_override("separation", 15)
		# Force consistent width across all chapters
		chapter_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chapter_container.custom_minimum_size.x = 800  # Adjust this value if needed
		
		# Chapter header
		var chapter_header = Label.new()
		chapter_header.text = chapter_data["header_text"]
		chapter_header.add_theme_font_size_override("font_size", 28)
		chapter_header.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
		chapter_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		chapter_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chapter_container.add_child(chapter_header)
		
		# Separator line
		var separator = HSeparator.new()
		chapter_container.add_child(separator)
		
		# Verses container
		var verses_container = VBoxContainer.new()
		verses_container.add_theme_constant_override("separation", 12)
		verses_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for verse_data in chapter_data["verses"]:
			if verse_data["has_edit"]:
				# Use RichTextLabel for edited verses to show inline highlights
				var verse_label = RichTextLabel.new()
				verse_label.bbcode_enabled = true
				verse_label.fit_content = true
				verse_label.scroll_active = false
				verse_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				verse_label.add_theme_font_size_override("normal_font_size", 24)
				# Add background color to highlight edited verse
				verse_label.add_theme_color_override("default_color", Color(0.95, 0.95, 0.85))
				verse_label.text = verse_data["bbcode"]
				verses_container.add_child(verse_label)
			else:
				# Use Label for unedited verses (faster)
				var verse_label = Label.new()
				verse_label.text = verse_data["text"]
				verse_label.add_theme_font_size_override("font_size", 24)
				verse_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
				verse_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				verse_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				verses_container.add_child(verse_label)
		
		chapter_container.add_child(verses_container)
		
		# Add spacing after chapter
		var spacer = Control.new()
		spacer.custom_minimum_size.y = 40
		chapter_container.add_child(spacer)
		
		# Track chapter container for scroll position tracking
		chapter_containers.append(chapter_container)
		pages_content.add_child(chapter_container)

func _prepare_pages_data():
	# Pre-compute all chapter and verse data for faster rendering
	pages_chapter_data.clear()
	
	var chapter_keys = book.chapters.keys()
	chapter_keys.sort()
	
	for chapter_num in chapter_keys:
		var chapter_verses = book.chapters[chapter_num]
		var chapter_title = book.chapter_titles[chapter_num - 1] if chapter_num - 1 < book.chapter_titles.size() else ""
		
		var chapter_data = {
			"header_text": "Chapter %d: %s" % [chapter_num, chapter_title],
			"verses": []
		}
		
		for verse_idx in range(chapter_verses.size()):
			var verse_data = chapter_verses[verse_idx]
			var verse_num = verse_data["verse"] if verse_data.has("verse") else verse_idx + 1
			var original_text = verse_data["text"] if verse_data.has("text") else ""
			
			# Check if this verse has been edited
			var verse_key = "Chapter %d, Verse %d" % [chapter_num, verse_num]
			var has_edit = edited_verses.has(verse_key)
			
			if has_edit:
				var edited_text = edited_verses[verse_key]
				var highlighted_text = _highlight_changes(original_text, edited_text)
				chapter_data["verses"].append({
					"has_edit": true,
					"bbcode": "[color=#ffda66]✱[/color] [color=#888888]%d.[/color] %s" % [verse_num, highlighted_text],
					"text": ""
				})
			else:
				chapter_data["verses"].append({
					"has_edit": false,
					"bbcode": "",
					"text": "%d. %s" % [verse_num, original_text]
				})
		
		pages_chapter_data.append(chapter_data)
	
	pages_data_cached = true

func _highlight_changes(original: String, edited: String) -> String:
	# Word-by-word diff to highlight only changed portions
	var orig_words = original.split(" ")
	var edit_words = edited.split(" ")
	
	var result = ""
	var i = 0
	var j = 0
	
	while i < orig_words.size() or j < edit_words.size():
		if i >= orig_words.size():
			# Extra words added at end
			while j < edit_words.size():
				result += "[color=#ffda66]" + edit_words[j] + "[/color] "
				j += 1
		elif j >= edit_words.size():
			# Words removed from end - skip them (they're gone)
			break
		elif orig_words[i] == edit_words[j]:
			# Words match - show in white
			result += "[color=#ffffff]" + edit_words[j] + "[/color] "
			i += 1
			j += 1
		else:
			# Words differ - find how many consecutive different words
			var edit_start = j
			var found_match = false
			
			# Look ahead in edited to find next matching word from original
			for look_ahead in range(1, mini(10, edit_words.size() - j)):
				if i < orig_words.size() and j + look_ahead < edit_words.size():
					if orig_words[i] == edit_words[j + look_ahead]:
						# Found where they sync up again - highlight the changed portion
						while j < edit_start + look_ahead:
							result += "[color=#ffda66]" + edit_words[j] + "[/color] "
							j += 1
						found_match = true
						break
			
			if not found_match:
				# Check if original word was replaced
				var orig_found_later = false
				for look_ahead in range(1, mini(10, orig_words.size() - i)):
					if i + look_ahead < orig_words.size() and j < edit_words.size():
						if orig_words[i + look_ahead] == edit_words[j]:
							# Original words were deleted, skip them
							i += look_ahead
							orig_found_later = true
							break
				
				if not orig_found_later:
					# Simple replacement - highlight the edited word
					result += "[color=#ffda66]" + edit_words[j] + "[/color] "
					i += 1
					j += 1
	
	return result.strip_edges()

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
			chapter_header.text = "*" + chapter_text
		else:
			chapter_header.text = chapter_text
		
		chapter_header.add_theme_font_size_override("font_size", 20)
		chapter_header.flat = true
		chapter_header.alignment = HORIZONTAL_ALIGNMENT_LEFT
		chapter_header.custom_minimum_size.x = 500
		
		# Color edited chapters differently
		if has_edits:
			chapter_header.add_theme_color_override("font_color", Color(1.0, 0.8, 0.6))
		
		# Highlight if this is the current chapter (entry["chapter"] is 1-based, book.current_chapter is 1-based)
		if entry["chapter"] == book.current_chapter:
			chapter_header.text = ">" + chapter_text
			chapter_header.add_theme_color_override("font_color", Color(0.3, 0.7, 1.0))
		
		var verse_grid = GridContainer.new()
		verse_grid.columns = 10
		var chapter_index = entry["chapter"] - 1
		# Only expand if it was previously expanded in session data
		verse_grid.visible = session_data.expanded_chapters.get(chapter_index, false)
		verse_grids[chapter_index] = verse_grid
		
		chapter_section.add_child(chapter_header)
		chapter_section.add_child(verse_grid)
		
		chapter_header.pressed.connect(_on_chapter_header_pressed.bind(chapter_index))
		
		for verse in range(entry["verse_count"]):
			var verse_button = Button.new()
			var verse_key = "Chapter %d, Verse %d" % [entry["chapter"], verse + 1]
			
			# Add visual indicator for edited verses
			if edited_verses.has(verse_key):
				verse_button.text = str(verse + 1) + "*"
				verse_button.add_theme_color_override("font_color", Color(1.0, 0.8, 0.6))
			else:
				verse_button.text = str(verse + 1)
			
			# Make verse buttons twice as big (60x60 instead of 30x30)
			verse_button.custom_minimum_size = Vector2(35, 35)
			verse_button.add_theme_font_size_override("font_size", 18)
			verse_button.pressed.connect(_on_verse_button_pressed.bind(chapter_index, verse))
			
			# Highlight current verse (entry["chapter"] is 1-based = book.current_chapter, verse is 0-based = book.current_verse)
			if entry["chapter"] == book.current_chapter and verse == book.current_verse:
				verse_button.add_theme_color_override("font_color", Color(0.3, 0.7, 1.0))
			
			verse_grid.add_child(verse_button)
		
		toc_container.add_child(chapter_section)

func _on_chapter_header_pressed(chapter: int):
	# chapter is 0-based index, book.current_chapter is 1-based
	# Prevent collapsing the currently selected chapter
	if chapter + 1 == book.current_chapter:
		return
	
	var verse_grid = verse_grids[chapter]
	verse_grid.visible = !verse_grid.visible
	session_data.expanded_chapters[chapter] = verse_grid.visible
	save_session_data()

func update_display():
	var current_text = book.get_current_text()
	text_display.text = current_text
	
	var chapter_verse = book.get_chapter_verse()
	var saved_edit = load_edit(chapter_verse)
	edited_text_display.text = saved_edit if saved_edit else current_text
	
	# Get chapter title and display with full format
	var chapter_title = book.chapter_titles[book.current_chapter - 1] if book.current_chapter - 1 < book.chapter_titles.size() else ""
	chapter_verse_label.text = "%s: %s" % [chapter_verse, chapter_title]
	
	update_toc_selection(book.current_chapter, book.current_verse)
	
	update_toc_edit_indicators()
	apply_search_highlighting()

func update_toc_selection(chapter: int, verse: int):
	# chapter is 1-based (from book.current_chapter), verse is 0-based (from book.current_verse)
	var chapter_idx = chapter - 1  # Convert to 0-based for TOC indexing
	
	# Reset previous verse selection only
	if current_verse_button:
		current_verse_button.modulate = Color(1, 1, 1)
		if current_verse_button.has_theme_color_override("font_color"):
			current_verse_button.remove_theme_color_override("font_color")
	
	# Update current selections
	if chapter_idx >= 0 and chapter_idx < toc_container.get_child_count():
		var chapter_section = toc_container.get_child(chapter_idx)
		if chapter_section:
			current_chapter_button = chapter_section.get_child(0)  # Chapter header button
			
			# Check if this chapter has edits (preserve the edit indicator color)
			var has_edits = false
			for v in range(book.chapters[chapter].size()):
				var check_key = "Chapter %d, Verse %d" % [chapter, v + 1]
				if edited_verses.has(check_key):
					has_edits = true
					break
			
			if has_edits:
				current_chapter_button.add_theme_color_override("font_color", Color(1.0, 0.8, 0.6))
			else:
				current_chapter_button.add_theme_color_override("font_color", Color(0.3, 0.7, 1.0))
			
			var verse_grid = verse_grids[chapter_idx]
			if verse >= 0 and verse_grid and verse < verse_grid.get_child_count():
				current_verse_button = verse_grid.get_child(verse)
				current_verse_button.add_theme_color_override("font_color", Color(0.3, 0.7, 1.0))
				
				# Ensure current chapter is expanded
				if not verse_grid.visible:
					verse_grid.visible = true
					session_data.expanded_chapters[chapter_idx] = true
					save_session_data()

func update_toc_edit_indicators():
	# Store current expanded states
	var current_expanded_states = {}
	for chapter_idx in verse_grids:
		if verse_grids[chapter_idx]:
			current_expanded_states[chapter_idx] = verse_grids[chapter_idx].visible
	
	# Setup TOC
	setup_toc()
	
	# Restore expanded states
	for chapter_idx in current_expanded_states:
		if verse_grids.has(chapter_idx) and verse_grids[chapter_idx]:
			verse_grids[chapter_idx].visible = current_expanded_states[chapter_idx]
			session_data.expanded_chapters[chapter_idx] = current_expanded_states[chapter_idx]

func _on_save_button_pressed():
	var chapter_verse = book.get_chapter_verse()
	var original_text = text_display.text
	var edited_text = edited_text_display.text
	
	# Don't save if text hasn't changed
	if original_text == edited_text:
		print("No changes to save for " + chapter_verse)
		return
	
	save_edit(chapter_verse, edited_text)
	update_toc_edit_indicators()
	save_session_data()

func _on_changes_clear_button_pressed():
	edited_text_display.text = text_display.text
	var chapter_verse = book.get_chapter_verse()
	clear_edit(chapter_verse)
	# Update TOC to remove edit indicator
	update_toc_edit_indicators()

func save_edit(chapter_verse: String, text: String):
	var save_data = {}
	
	# Load existing saves first - web compatible
	if OS.has_feature("web"):
		var json_string = _web_storage_get("revelation_edited_verses")
		if json_string != "":
			var data = JSON.parse_string(json_string)
			if data:
				save_data = data
	else:
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
	
	# Invalidate pages cache
	pages_data_cached = false
	
	# Save back - web compatible
	if OS.has_feature("web"):
		var json_string = JSON.stringify(save_data)
		_web_storage_set("revelation_edited_verses", json_string)
		print("Saved edit for " + chapter_verse)
	else:
		var write_file = FileAccess.open("user://edited_verses.json", FileAccess.WRITE)
		if write_file:
			write_file.store_string(JSON.stringify(save_data))
			write_file.close()
			print("Saved edit for " + chapter_verse)
		else:
			print("Error: Could not save edit")

func load_edit(chapter_verse: String) -> String:
	# Web compatible loading
	if OS.has_feature("web"):
		var json_string = _web_storage_get("revelation_edited_verses")
		if json_string != "":
			var data = JSON.parse_string(json_string)
			if data and data.has(chapter_verse):
				return data[chapter_verse]
	else:
		var read_file = FileAccess.open("user://edited_verses.json", FileAccess.READ)
		if read_file:
			var data = JSON.parse_string(read_file.get_as_text())
			read_file.close()
			if data and data.has(chapter_verse):
				return data[chapter_verse]
	return ""

func clear_edit(chapter_verse: String):
	var save_data = {}
	
	# Load existing saves first - web compatible
	if OS.has_feature("web"):
		var json_string = _web_storage_get("revelation_edited_verses")
		if json_string != "":
			var data = JSON.parse_string(json_string)
			if data:
				save_data = data
	else:
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
		
		# Invalidate pages cache
		pages_data_cached = false
		
		# Save back - web compatible
		if OS.has_feature("web"):
			var json_string = JSON.stringify(save_data)
			_web_storage_set("revelation_edited_verses", json_string)
			print("Cleared edit for " + chapter_verse)
		else:
			var write_file = FileAccess.open("user://edited_verses.json", FileAccess.WRITE)
			if write_file:
				write_file.store_string(JSON.stringify(save_data))
				write_file.close()
				print("Cleared edit for " + chapter_verse)
			else:
				print("Error: Could not save after clearing edit")

func load_edited_verses():
	# Web compatible loading
	if OS.has_feature("web"):
		var json_string = _web_storage_get("revelation_edited_verses")
		if json_string != "":
			var data = JSON.parse_string(json_string)
			if data:
				edited_verses = data
			else:
				edited_verses = {}
		else:
			edited_verses = {}
	else:
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
	
	# If no edited verses exist, create default edit for Chapter 1, Verse 1
	if edited_verses.is_empty():
		var default_verse_key = "Chapter 1, Verse 1"
		var default_verse_text = "The Revelation of Gaben, which God gave unto him, to shew unto his servants things which must soon™ come to pass; and he sent and signified it by his angel unto his servant John: 🎱"
		
		edited_verses[default_verse_key] = default_verse_text
		
		# Save the default edit - web compatible
		if OS.has_feature("web"):
			var json_string = JSON.stringify(edited_verses)
			_web_storage_set("revelation_edited_verses", json_string)
			print("Created default edit for " + default_verse_key)
		else:
			var write_file = FileAccess.open("user://edited_verses.json", FileAccess.WRITE)
			if write_file:
				write_file.store_string(JSON.stringify(edited_verses))
				write_file.close()
				print("Created default edit for " + default_verse_key)

func display_search_results(results: Array, search_text: String):
	# Clear previous results
	for child in search_results_list.get_children():
		child.queue_free()
	
	for result in results:
		var result_container = VBoxContainer.new()
		result_container.add_theme_constant_override("separation", 5)
		
		# Create clickable header
		var header_button = Button.new()
		header_button.text = "Chapter %d, Verse %d" % [result["chapter"], result["verse"]]
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

func escape_regex_string(string: String) -> String:
	# Escape special regex characters
	var special_chars = ["\\", ".", "+", "*", "?", "^", "$", "(", ")", "[", "]", "{", "}", "|"]
	var escaped = string
	for special_char in special_chars:
		escaped = escaped.replace(special_char, "\\" + special_char)
	return escaped

func highlight_search_terms(text: String, search_terms: String) -> String:
	var words = search_terms.to_lower().split(" ")
	var highlighted = text
	var text_words = text.to_lower().split(" ")
	
	# Find all words to highlight (exact and fuzzy matches)
	var words_to_highlight = []
	
	for search_word in words:
		if search_word.length() >= 2:
			# Add exact matches
			words_to_highlight.append(search_word)
			
			# Find fuzzy matches in the text
			for text_word in text_words:
				var clean_text_word = clean_word_for_highlighting(text_word)
				if clean_text_word.length() >= 2:
					var similarity = calculate_similarity(search_word, clean_text_word)
					if similarity > 0.7 and clean_text_word != search_word:
						words_to_highlight.append(clean_text_word)
	
	# Remove duplicates
	var unique_words = {}
	for word in words_to_highlight:
		unique_words[word] = true
	
	# Apply highlighting with fuzzy matching
	for word in unique_words:
		if word.length() >= 2:
			var regex = RegEx.new()
			regex.compile("(?i)\\b" + escape_regex_string(word) + "\\b")
			highlighted = regex.sub(highlighted, "[bgcolor=#ffff00][color=#000000]$0[/color][/bgcolor]", true)
	
	return highlighted

func highlight_text_in_display(text_edit: TextEdit, search_terms: String):
	# Clear previous search highlighting by removing syntax highlighter
	if text_edit.syntax_highlighter != null:
		text_edit.syntax_highlighter = null
	
	if search_terms.length() < 2:
		return
	
	# Create a new syntax highlighter for search terms
	var highlighter = CodeHighlighter.new()
	
	# Split search terms into individual words
	var words = search_terms.to_lower().split(" ")
	var text_content = text_edit.text.to_lower()
	
	# Find all matching words and phrases in the text
	var matches_to_highlight = []
	
	# First, try to match the complete search phrase
	if search_terms.length() >= 2:
		var phrase_matches = find_phrase_matches(text_content, search_terms.to_lower())
		matches_to_highlight.append_array(phrase_matches)
	
	# Then match individual words with fuzzy matching
	for search_word in words:
		if search_word.length() >= 2:
			var word_matches = find_word_matches(text_content, search_word)
			matches_to_highlight.append_array(word_matches)
	
	# Remove duplicates and apply highlighting
	var unique_matches = {}
	for match in matches_to_highlight:
		unique_matches[match] = true
	
	# Add color highlighting for each unique match
	for match in unique_matches:
		if match.length() >= 2:
			highlighter.add_keyword_color(match, Color.YELLOW)
			# Also add variations with different cases
			highlighter.add_keyword_color(match.capitalize(), Color.YELLOW)
			highlighter.add_keyword_color(match.to_upper(), Color.YELLOW)
	
	text_edit.syntax_highlighter = highlighter

func find_phrase_matches(text: String, phrase: String) -> Array:
	var matches = []
	var start = 0
	
	while start < text.length():
		var index = text.find(phrase, start)
		if index == -1:
			break
		
		# Extract the actual text from the original (preserving case)
		var actual_phrase = text.substr(index, phrase.length())
		matches.append(actual_phrase)
		start = index + phrase.length()
	
	return matches

func find_word_matches(text: String, search_word: String) -> Array:
	var matches = []
	var words = text.split(" ")
	
	for word in words:
		var clean_word = clean_word_for_highlighting(word)
		if clean_word.length() >= 2:
			# Check for exact match
			if clean_word == search_word:
				matches.append(clean_word)
			else:
				# Check for fuzzy match
				var similarity = calculate_similarity(search_word, clean_word)
				if similarity > 0.7:
					matches.append(clean_word)
	
	return matches

func clean_word_for_highlighting(word: String) -> String:
	# Remove common punctuation and convert to lowercase
	var cleaned = word.to_lower()
	cleaned = cleaned.replace(",", "")
	cleaned = cleaned.replace(".", "")
	cleaned = cleaned.replace(";", "")
	cleaned = cleaned.replace(":", "")
	cleaned = cleaned.replace("!", "")
	cleaned = cleaned.replace("?", "")
	cleaned = cleaned.replace("\"", "")
	cleaned = cleaned.replace("(", "")
	cleaned = cleaned.replace(")", "")
	cleaned = cleaned.replace("[", "")
	cleaned = cleaned.replace("]", "")
	return cleaned.strip_edges()

func calculate_similarity(word1: String, word2: String) -> float:
	if word1 == word2:
		return 1.0
	
	var len1 = word1.length()
	var len2 = word2.length()
	
	# Quick length check - if too different, low similarity
	if abs(len1 - len2) > max(len1, len2) * 0.5:
		return 0.0
	
	# Levenshtein distance calculation
	var matrix = []
	for i in range(len1 + 1):
		matrix.append([])
		for j in range(len2 + 1):
			matrix[i].append(0)
	
	for i in range(len1 + 1):
		matrix[i][0] = i
	for j in range(len2 + 1):
		matrix[0][j] = j
	
	for i in range(1, len1 + 1):
		for j in range(1, len2 + 1):
			var cost = 0 if word1[i-1] == word2[j-1] else 1
			matrix[i][j] = min(
				matrix[i-1][j] + 1,      # deletion
				matrix[i][j-1] + 1,      # insertion
				matrix[i-1][j-1] + cost  # substitution
			)
	
	var distance = matrix[len1][len2]
	var max_len = max(len1, len2)
	return 1.0 - (float(distance) / float(max_len))

func apply_search_highlighting():
	# Apply search highlighting to both original and edited text displays
	if last_search_text.length() >= 2:
		highlight_text_in_display(text_display, last_search_text)
		highlight_text_in_display(edited_text_display, last_search_text)

func clear_search_highlighting():
	# Clear search highlighting from both text displays
	if text_display.syntax_highlighter != null:
		text_display.syntax_highlighter = null
	if edited_text_display.syntax_highlighter != null:
		edited_text_display.syntax_highlighter = null

func _exit_tree():
	save_session_data()
