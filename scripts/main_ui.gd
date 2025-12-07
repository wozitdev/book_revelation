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
@onready var export_button = $MarginContainer/VBoxContainer/ButtonContainer/EditActions/ExportButton
@onready var import_button = $MarginContainer/VBoxContainer/ButtonContainer/EditActions/ImportButton
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
var file_dialog: FileDialog
var pending_export_text = ""  # Text waiting to be exported
var pending_export_format = ""  # Track which format to export (json or txt)
var showing_original = false  # Track if currently showing original text

# Lazy loading variables
var pages_data_cached = false
var pages_chapter_data = []  # Pre-computed chapter data for faster rendering

# Live highlighting variables
var current_original_text = ""  # Original text for comparison
var previous_edited_text = ""   # Previous state for detecting changes
var previous_caret_column = 0   # Previous cursor position
var previous_caret_line = 0
var is_updating_text = false    # Flag to prevent recursive updates
var edit_highlighter: CodeHighlighter = null

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
		export_button.pressed.connect(_on_export_button_pressed)
		import_button.pressed.connect(_on_import_button_pressed)
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
		
		# Setup live inline highlighting
		_setup_inline_highlighter()
		edited_text_display.text_changed.connect(_on_edited_text_changed)
		
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

func _highlight_changes(_original: String, edited: String) -> String:
	# Process revision tags for Pages view display using BBCode
	# [rev_del] content is removed entirely (it's deleted text)
	# [rev_add] content is shown in green
	# [rev_mod] content is shown in yellow
	
	var result = edited
	
	# Remove [rev_del] tags and their contents entirely
	var del_regex = RegEx.new()
	del_regex.compile("\\[rev_del\\].*?\\[/rev_del\\]")
	result = del_regex.sub(result, "", true)
	
	# Convert [rev_add] to green BBCode
	result = result.replace("[rev_add]", "[color=#66ff66]")
	result = result.replace("[/rev_add]", "[/color]")
	
	# Convert [rev_mod] to yellow BBCode
	result = result.replace("[rev_mod]", "[color=#ffda66]")
	result = result.replace("[/rev_mod]", "[/color]")
	
	# Clean up double spaces
	result = result.replace("  ", " ").strip_edges()
	
	return result

# ============================================================================
# AUTOMATIC DIFF TAGGING SYSTEM
# ============================================================================

func _strip_all_tags(text: String) -> String:
	# Remove all revision tags AND display markers from text to get clean content
	var result = text
	
	# Remove storage tags (delete tags remove content, add/mod keep content)
	var del_regex = RegEx.new()
	del_regex.compile("\\[rev_del\\].*?\\[/rev_del\\]")
	result = del_regex.sub(result, "", true)
	result = result.replace("[rev_add]", "").replace("[/rev_add]", "")
	result = result.replace("[rev_mod]", "").replace("[/rev_mod]", "")
	
	# Remove display markers (deletion markers remove content too)
	var display_del_regex = RegEx.new()
	display_del_regex.compile("\\[/[^/]*/\\]")
	result = display_del_regex.sub(result, "", true)
	result = result.replace("[+", "").replace("+]", "")
	result = result.replace("[*", "").replace("*]", "")
	
	# Clean up double spaces
	while result.contains("  "):
		result = result.replace("  ", " ")
	return result.strip_edges()

func _tokenize_text(text: String) -> Array:
	# Split text into tokens (words and punctuation) preserving order
	var tokens = []
	var current_word = ""
	
	for i in range(text.length()):
		var c = text[i]
		if c == " " or c == "\n" or c == "\t":
			if current_word != "":
				tokens.append(current_word)
				current_word = ""
		elif c in [".", ",", ";", ":", "!", "?", "(", ")", "[", "]", "\"", "'"]:
			if current_word != "":
				tokens.append(current_word)
				current_word = ""
			tokens.append(c)
		else:
			current_word += c
	
	if current_word != "":
		tokens.append(current_word)
	
	return tokens

func _compute_lcs_table(tokens_a: Array, tokens_b: Array) -> Array:
	# Compute Longest Common Subsequence table
	var m = tokens_a.size()
	var n = tokens_b.size()
	var dp = []
	
	for i in range(m + 1):
		var row = []
		for j in range(n + 1):
			row.append(0)
		dp.append(row)
	
	for i in range(1, m + 1):
		for j in range(1, n + 1):
			if tokens_a[i - 1] == tokens_b[j - 1]:
				dp[i][j] = dp[i - 1][j - 1] + 1
			else:
				dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
	
	return dp

func _backtrack_diff(tokens_a: Array, tokens_b: Array, dp: Array) -> Array:
	# Backtrack through LCS table to generate diff operations
	# Returns array of {"op": "keep"|"del"|"add", "token": String}
	var diff = []
	var i = tokens_a.size()
	var j = tokens_b.size()
	
	while i > 0 or j > 0:
		if i > 0 and j > 0 and tokens_a[i - 1] == tokens_b[j - 1]:
			diff.push_front({"op": "keep", "token": tokens_a[i - 1]})
			i -= 1
			j -= 1
		elif j > 0 and (i == 0 or dp[i][j - 1] >= dp[i - 1][j]):
			diff.push_front({"op": "add", "token": tokens_b[j - 1]})
			j -= 1
		else:
			diff.push_front({"op": "del", "token": tokens_a[i - 1]})
			i -= 1
	
	return diff

func _detect_modifications(diff: Array) -> Array:
	# Post-process diff to detect modifications (del immediately followed by add)
	var result = []
	var i = 0
	
	while i < diff.size():
		var current = diff[i]
		
		# Look for del followed by add pattern (modification)
		if current.op == "del":
			# Collect consecutive deletions
			var del_tokens = []
			while i < diff.size() and diff[i].op == "del":
				del_tokens.append(diff[i].token)
				i += 1
			
			# Check if followed by additions
			var add_tokens = []
			while i < diff.size() and diff[i].op == "add":
				add_tokens.append(diff[i].token)
				i += 1
			
			# Decide if it's a modification or separate del/add
			if del_tokens.size() > 0 and add_tokens.size() > 0:
				# Check if they look like a modification (similar length, similar position)
				var is_modification = _looks_like_modification(del_tokens, add_tokens)
				if is_modification:
					# Mark as modification
					for token in del_tokens:
						result.append({"op": "del", "token": token})
					for token in add_tokens:
						result.append({"op": "mod", "token": token})
				else:
					# Keep as separate del and add
					for token in del_tokens:
						result.append({"op": "del", "token": token})
					for token in add_tokens:
						result.append({"op": "add", "token": token})
			else:
				# Just deletions or just additions
				for token in del_tokens:
					result.append({"op": "del", "token": token})
				for token in add_tokens:
					result.append({"op": "add", "token": token})
		else:
			result.append(current)
			i += 1
	
	return result

func _looks_like_modification(del_tokens: Array, add_tokens: Array) -> bool:
	# Heuristic to determine if del+add is actually a modification
	# Consider it a modification if:
	# 1. Similar word count (within 2 words)
	# 2. Or the tokens have some character similarity
	
	var len_diff = abs(del_tokens.size() - add_tokens.size())
	if len_diff <= 2:
		return true
	
	# Check if any words are similar (partial match)
	for del_token in del_tokens:
		for add_token in add_tokens:
			if _word_similarity(del_token, add_token) > 0.5:
				return true
	
	return false

func _word_similarity(word1: String, word2: String) -> float:
	# Simple character-based similarity
	var w1 = word1.to_lower()
	var w2 = word2.to_lower()
	
	if w1 == w2:
		return 1.0
	
	# Check prefix match
	var min_len = min(w1.length(), w2.length())
	var common_prefix = 0
	for i in range(min_len):
		if w1[i] == w2[i]:
			common_prefix += 1
		else:
			break
	
	var max_len = max(w1.length(), w2.length())
	return float(common_prefix) / float(max_len)

func _build_tagged_text(diff: Array) -> String:
	# Build the final text with appropriate tags
	var result = ""
	var i = 0
	
	while i < diff.size():
		var current = diff[i]
		
		if current.op == "keep":
			if result != "" and not result.ends_with(" ") and not current.token in [".", ",", ";", ":", "!", "?", ")", "]", "\""]:
				result += " "
			result += current.token
			i += 1
		elif current.op == "del":
			# Collect consecutive deletions
			var del_tokens = []
			while i < diff.size() and diff[i].op == "del":
				del_tokens.append(diff[i].token)
				i += 1
			if del_tokens.size() > 0:
				if result != "" and not result.ends_with(" "):
					result += " "
				result += "[rev_del]" + " ".join(del_tokens) + "[/rev_del]"
		elif current.op == "add":
			# Collect consecutive additions
			var add_tokens = []
			while i < diff.size() and diff[i].op == "add":
				add_tokens.append(diff[i].token)
				i += 1
			if add_tokens.size() > 0:
				if result != "" and not result.ends_with(" ") and not add_tokens[0] in [".", ",", ";", ":", "!", "?", ")", "]", "\""]:
					result += " "
				result += "[rev_add]" + " ".join(add_tokens) + "[/rev_add]"
		elif current.op == "mod":
			# Collect consecutive modifications
			var mod_tokens = []
			while i < diff.size() and diff[i].op == "mod":
				mod_tokens.append(diff[i].token)
				i += 1
			if mod_tokens.size() > 0:
				if result != "" and not result.ends_with(" ") and not mod_tokens[0] in [".", ",", ";", ":", "!", "?", ")", "]", "\""]:
					result += " "
				result += "[rev_mod]" + " ".join(mod_tokens) + "[/rev_mod]"
	
	# Clean up spacing around punctuation
	result = result.replace(" .", ".").replace(" ,", ",").replace(" ;", ";")
	result = result.replace(" :", ":").replace(" !", "!").replace(" ?", "?")
	result = result.replace("( ", "(").replace(" )", ")")
	
	# Clean up double spaces
	while result.contains("  "):
		result = result.replace("  ", " ")
	
	return result.strip_edges()

func generate_auto_tags(original: String, edited: String) -> String:
	# Main function to automatically generate revision tags
	# by comparing original text with edited text
	
	# Strip any existing tags from edited text to get clean comparison
	var clean_edited = _strip_all_tags(edited)
	
	# If no actual changes, return original
	if original.strip_edges() == clean_edited:
		return original
	
	# Tokenize both texts
	var tokens_original = _tokenize_text(original)
	var tokens_edited = _tokenize_text(clean_edited)
	
	# Compute LCS and generate diff
	var dp = _compute_lcs_table(tokens_original, tokens_edited)
	var diff = _backtrack_diff(tokens_original, tokens_edited, dp)
	
	# Detect modifications (del+add at same position)
	diff = _detect_modifications(diff)
	
	# Build final tagged text
	return _build_tagged_text(diff)

# ============================================================================
# LIVE INLINE HIGHLIGHTING SYSTEM
# Display markers: [] for add, [/] for del, [*] for mod
# Storage tags: [rev_add][/rev_add], [rev_del][/rev_del], [rev_mod][/rev_mod]
# ============================================================================

func _setup_inline_highlighter():
	# Create CodeHighlighter for coloring tagged regions
	edit_highlighter = CodeHighlighter.new()
	edit_highlighter.number_color = Color(1, 1, 1)
	edit_highlighter.symbol_color = Color(1, 1, 1)
	edit_highlighter.function_color = Color(1, 1, 1)
	edit_highlighter.member_variable_color = Color(1, 1, 1)
	
	# Display markers for live editing:
	# [/text/] = red (deletion - original text being removed)
	# [text] = green (addition - new text)
	# [*text*] = yellow (modification - replacement text)
	edit_highlighter.add_color_region("[/", "/]", Color(1.0, 0.3, 0.3), false)  # Red for deletions
	edit_highlighter.add_color_region("[+", "+]", Color(0.4, 1.0, 0.4), false)  # Green for additions  
	edit_highlighter.add_color_region("[*", "*]", Color(1.0, 0.855, 0.4), false)  # Yellow for modifications
	
	edited_text_display.syntax_highlighter = edit_highlighter

func _on_edited_text_changed():
	if is_updating_text:
		return
	
	var current_text = edited_text_display.text
	var caret_line = edited_text_display.get_caret_line()
	var caret_column = edited_text_display.get_caret_column()
	
	# Get clean versions (strip display markers)
	var clean_current = _strip_display_markers(current_text)
	var clean_previous = _strip_display_markers(previous_edited_text)
	
	# Only process if actual content changed
	if clean_current != clean_previous:
		# Detect the type of edit based on what happened
		var edit_info = _detect_edit_type(clean_previous, clean_current, previous_caret_column, caret_column)
		
		# Apply the appropriate marking
		_apply_live_markers(edit_info, caret_line, caret_column)
	
	# Update previous state
	previous_edited_text = edited_text_display.text
	previous_caret_line = edited_text_display.get_caret_line()
	previous_caret_column = edited_text_display.get_caret_column()

func _strip_display_markers(text: String) -> String:
	# Remove display markers but handle deletion markers specially
	# Deletion markers [/text/] - the text inside should be removed from clean version
	var result = text
	
	# Remove deletion markers AND their content (deleted text shouldn't be in clean)
	var del_regex = RegEx.new()
	del_regex.compile("\\[/[^/]*/\\]")
	result = del_regex.sub(result, "", true)
	
	# Remove add/mod markers but keep content
	result = result.replace("[+", "").replace("+]", "")
	result = result.replace("[*", "").replace("*]", "")
	
	return result

func _detect_edit_type(old_text: String, new_text: String, _old_caret: int, new_caret: int) -> Dictionary:
	# Detect what type of edit occurred based on text changes and caret movement
	var info = {
		"type": "none",  # "add", "del", "mod"
		"position": new_caret,
		"old_text": old_text,
		"new_text": new_text,
		"changed_content": ""
	}
	
	var old_len = old_text.length()
	var new_len = new_text.length()
	
	if new_len > old_len:
		# Text got longer = addition
		info.type = "add"
		# Find what was added
		var added_len = new_len - old_len
		var add_start = new_caret - added_len
		if add_start >= 0 and add_start + added_len <= new_len:
			info.changed_content = new_text.substr(add_start, added_len)
			info.position = add_start
	elif new_len < old_len:
		# Text got shorter = deletion
		info.type = "del"
		# Find what was deleted
		var del_len = old_len - new_len
		var del_start = new_caret
		if del_start >= 0 and del_start + del_len <= old_len:
			info.changed_content = old_text.substr(del_start, del_len)
			info.position = del_start
	
	return info

func _apply_live_markers(edit_info: Dictionary, caret_line: int, caret_column: int):
	if edit_info.type == "none":
		return
	
	# Get the current displayed text (with old markers)
	var current_display_text = edited_text_display.text
	
	# Get current clean text
	var clean_text = _strip_display_markers(current_display_text)
	
	# Check if text now matches original - if so, clear all markers
	if clean_text.strip_edges() == current_original_text.strip_edges():
		is_updating_text = true
		edited_text_display.text = clean_text
		edited_text_display.set_caret_line(caret_line)
		edited_text_display.set_caret_column(caret_column)
		is_updating_text = false
		edited_text_display.grab_focus()
		return
	
	# First: convert caret position from OLD marked text to clean text position
	var clean_caret = _marked_to_clean_position(current_display_text, caret_line, caret_column)
	
	# Build new marked text
	var marked_text = _build_display_text(current_original_text, clean_text)
	
	# Then: convert clean position to NEW marked text position
	var new_caret = _clean_to_marked_position(clean_text, marked_text, clean_caret.line, clean_caret.column)
	
	is_updating_text = true
	edited_text_display.text = marked_text
	edited_text_display.set_caret_line(new_caret.line)
	edited_text_display.set_caret_column(new_caret.column)
	is_updating_text = false
	edited_text_display.grab_focus()

func _marked_to_clean_position(marked_text: String, line: int, column: int) -> Dictionary:
	# Convert a position in marked text to position in clean text
	# (skip marker characters when counting)
	
	var marked_lines = marked_text.split("\n")
	
	# Get the character index in the marked text
	var marked_char_idx = 0
	for l in range(min(line, marked_lines.size())):
		marked_char_idx += marked_lines[l].length() + 1
	if line < marked_lines.size():
		marked_char_idx += min(column, marked_lines[line].length())
	
	# Walk through marked text, counting clean characters
	var clean_char_idx = 0
	var i = 0
	
	while i < marked_text.length() and i < marked_char_idx:
		# Check for marker patterns
		if i + 1 < marked_text.length():
			var two = marked_text.substr(i, 2)
			if two == "[/" or two == "[+" or two == "[*":
				var close_marker = two[1] + "]"
				var end_pos = marked_text.find(close_marker, i + 2)
				if end_pos != -1:
					if two == "[/":
						# Deletion - skip entirely, no clean chars
						if i + 2 <= marked_char_idx:
							if end_pos + 2 <= marked_char_idx:
								# Cursor is past this whole marker
								i = end_pos + 2
								continue
							else:
								# Cursor is inside or at marker
								i = marked_char_idx
								continue
					else:
						# Add/mod - marker chars don't count, content does
						i += 2  # skip opening marker
						if i >= marked_char_idx:
							break
						# Count content chars
						while i < end_pos and i < marked_char_idx:
							i += 1
							clean_char_idx += 1
						if i >= marked_char_idx:
							break
						# Skip closing marker
						i += 2
						continue
		
		# Regular character
		i += 1
		clean_char_idx += 1
	
	# Convert clean_char_idx to line/column
	var clean_text = _strip_display_markers(marked_text)
	var clean_lines = clean_text.split("\n")
	var new_line = 0
	var pos = 0
	
	for l in range(clean_lines.size()):
		if pos + clean_lines[l].length() >= clean_char_idx:
			new_line = l
			break
		pos += clean_lines[l].length() + 1
		new_line = l
	
	var new_col = clean_char_idx - pos
	if new_line < clean_lines.size():
		new_col = min(new_col, clean_lines[new_line].length())
	
	return {"line": new_line, "column": max(0, new_col)}

func _clean_to_marked_position(clean_text: String, marked_text: String, line: int, column: int) -> Dictionary:
	# Convert a position in clean text to position in marked text
	
	# First, convert line/column to character index in clean text
	var clean_lines = clean_text.split("\n")
	var clean_char_idx = 0
	for l in range(min(line, clean_lines.size())):
		clean_char_idx += clean_lines[l].length() + 1  # +1 for newline
	if line < clean_lines.size():
		clean_char_idx += min(column, clean_lines[line].length())
	
	# Now find corresponding position in marked text
	# Walk through marked text, tracking "clean" characters seen
	var marked_idx = 0
	var clean_counted = 0
	var i = 0
	
	while i < marked_text.length():
		# Stop if we've counted enough clean characters
		if clean_counted >= clean_char_idx:
			break
		
		# Check for marker starts: [/ [+ [*
		if i + 1 < marked_text.length():
			var two = marked_text.substr(i, 2)
			if two == "[/" or two == "[+" or two == "[*":
				var close_marker = two[1] + "]"  # "/]" or "+]" or "*]"
				var end_pos = marked_text.find(close_marker, i + 2)
				if end_pos != -1:
					# For deletions [/text/], skip entirely (not in clean text)
					if two == "[/":
						i = end_pos + 2
						marked_idx = end_pos + 2
						continue
					else:
						# For adds [+text+] and mods [*text*], the content IS in clean text
						# Skip the opening marker
						i += 2
						marked_idx += 2
						# Now count the content characters
						while i < end_pos and clean_counted < clean_char_idx:
							i += 1
							marked_idx += 1
							clean_counted += 1
						# If we've reached our target, break
						if clean_counted >= clean_char_idx:
							break
						# Skip closing marker
						i += 2
						marked_idx += 2
						continue
		
		# Regular character - count it
		i += 1
		marked_idx += 1
		clean_counted += 1
	
	# Convert marked_idx back to line/column
	var marked_lines = marked_text.split("\n")
	var new_line = 0
	var pos_counted = 0
	
	for l in range(marked_lines.size()):
		var line_len = marked_lines[l].length()
		if pos_counted + line_len >= marked_idx:
			new_line = l
			break
		pos_counted += line_len + 1  # +1 for newline
		new_line = l
	
	var new_col = marked_idx - pos_counted
	if new_line < marked_lines.size():
		new_col = min(new_col, marked_lines[new_line].length())
	new_col = max(0, new_col)
	
	return {"line": new_line, "column": new_col}

func _build_display_text(original: String, edited: String) -> String:
	# Build text with display markers showing what changed
	# Compare word by word and mark:
	# - Words in original but not in edited position = [/deleted/]
	# - Words in edited but not in original = [+added+]
	# - Words that replaced others = [*modified*]
	
	var orig_words = _split_into_words(original)
	var edit_words = _split_into_words(edited)
	
	# Simple approach: find matching words and mark differences
	var result = ""
	var orig_idx = 0
	var edit_idx = 0
	
	while orig_idx < orig_words.size() or edit_idx < edit_words.size():
		if orig_idx >= orig_words.size():
			# Remaining edited words are additions
			while edit_idx < edit_words.size():
				if result != "" and not result.ends_with(" ") and not _is_punctuation(edit_words[edit_idx]):
					result += " "
				result += "[+" + edit_words[edit_idx] + "+]"
				edit_idx += 1
			break
		
		if edit_idx >= edit_words.size():
			# Remaining original words are deletions
			while orig_idx < orig_words.size():
				if result != "" and not result.ends_with(" "):
					result += " "
				result += "[/" + orig_words[orig_idx] + "/]"
				orig_idx += 1
			break
		
		var orig_word = orig_words[orig_idx]
		var edit_word = edit_words[edit_idx]
		
		if orig_word == edit_word:
			# Words match - keep as is
			if result != "" and not result.ends_with(" ") and not _is_punctuation(orig_word):
				result += " "
			result += orig_word
			orig_idx += 1
			edit_idx += 1
		else:
			# Words differ - check if it's a modification or del+add
			# Look ahead to see if orig_word appears later in edit_words
			var orig_found_later = _find_word_ahead(orig_word, edit_words, edit_idx + 1)
			var edit_found_later = _find_word_ahead(edit_word, orig_words, orig_idx + 1)
			
			if not orig_found_later and not edit_found_later:
				# Neither word found ahead - it's a MODIFICATION (one word replaced another)
				# Only show the modified word, no deletion marker
				if result != "" and not result.ends_with(" "):
					result += " "
				result += "[*" + edit_word + "*]"
				orig_idx += 1
				edit_idx += 1
			elif orig_found_later:
				# Original word found later - current edit word is an addition
				if result != "" and not result.ends_with(" ") and not _is_punctuation(edit_word):
					result += " "
				result += "[+" + edit_word + "+]"
				edit_idx += 1
			else:
				# Edit word found later - current orig word is a deletion
				if result != "" and not result.ends_with(" "):
					result += " "
				result += "[/" + orig_word + "/]"
				orig_idx += 1
	
	# Clean up spacing
	result = result.replace(" .", ".").replace(" ,", ",").replace(" ;", ";")
	result = result.replace(" :", ":").replace(" !", "!").replace(" ?", "?")
	
	return result.strip_edges()

func _split_into_words(text: String) -> Array:
	# Split text into words, keeping punctuation attached
	var words = []
	var current = ""
	
	for i in range(text.length()):
		var c = text[i]
		if c == " " or c == "\n" or c == "\t":
			if current != "":
				words.append(current)
				current = ""
		else:
			current += c
	
	if current != "":
		words.append(current)
	
	return words

func _find_word_ahead(word: String, words: Array, start_idx: int) -> bool:
	# Check if word appears in words array starting from start_idx
	for i in range(start_idx, min(start_idx + 5, words.size())):  # Look max 5 words ahead
		if words[i] == word:
			return true
	return false

func _is_punctuation(token: String) -> bool:
	return token in [".", ",", ";", ":", "!", "?", ")", "]", "\"", "'"]

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
	
	# Store original text for live diff comparison
	current_original_text = current_text
	
	# Reset toggle state when changing verses
	showing_original = false
	
	var chapter_verse = book.get_chapter_verse()
	var saved_edit = load_edit(chapter_verse)
	
	# If there's a saved edit, extract clean text (strip tags) for display
	# User always sees clean text in the editor (or with markers if there are changes)
	var display_text: String
	if saved_edit:
		display_text = _strip_all_tags(saved_edit)
	else:
		display_text = current_text
	
	# Apply inline highlighter
	edited_text_display.syntax_highlighter = edit_highlighter
	
	# Set text and initialize previous state
	is_updating_text = true
	edited_text_display.text = display_text
	previous_edited_text = display_text
	is_updating_text = false
	
	# Rebuild with markers if there are changes
	if display_text.strip_edges() != current_text.strip_edges():
		var marked = _build_display_text(current_text, display_text)
		is_updating_text = true
		edited_text_display.text = marked
		previous_edited_text = marked
		is_updating_text = false
	
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
	
	# Strip display markers to get clean edited text
	var clean_edited = _strip_display_markers(edited_text)
	
	# Check if there are actual changes
	if original_text.strip_edges() == clean_edited.strip_edges():
		print("No changes to save for " + chapter_verse)
		return
	
	# Auto-generate storage tags based on diff
	var text_to_save = generate_auto_tags(original_text, clean_edited)
	
	# Save the edited text with storage tags
	save_edit(chapter_verse, text_to_save)
	
	# Update TOC
	update_toc_edit_indicators()
	save_session_data()
	
	print("Saved changes for " + chapter_verse)

func _on_changes_clear_button_pressed():
	var chapter_verse = book.get_chapter_verse()
	var original_text = text_display.text
	var saved_edit = edited_verses.get(chapter_verse, "")
	
	# Get clean versions for comparison (strip all markers and tags)
	var current_clean = _strip_display_markers(edited_text_display.text)
	current_clean = _strip_all_tags(current_clean).strip_edges()
	var original_clean = original_text.strip_edges()
	var saved_clean = _strip_all_tags(saved_edit).strip_edges() if saved_edit else ""
	
	if saved_edit != "" and current_clean != saved_clean:
		# Current is different from saved edit - load saved edit with live markers
		var display_text = _strip_all_tags(saved_edit)
		var marked_text = _build_display_text(original_text, display_text)
		is_updating_text = true
		edited_text_display.text = marked_text
		previous_edited_text = marked_text
		is_updating_text = false
	elif current_clean != original_clean:
		# Current differs from original - load original
		is_updating_text = true
		edited_text_display.text = original_text
		previous_edited_text = original_text
		is_updating_text = false
	elif saved_edit != "":
		# Current is original and there's a saved edit - load saved edit with live markers
		var display_text = _strip_all_tags(saved_edit)
		var marked_text = _build_display_text(original_text, display_text)
		is_updating_text = true
		edited_text_display.text = marked_text
		previous_edited_text = marked_text
		is_updating_text = false

func _on_export_button_pressed():
	# Use built-in ConfirmationDialog
	var dialog = ConfirmationDialog.new()
	dialog.title = "Export"
	dialog.dialog_text = ""
	dialog.ok_button_text = "TXT"
	dialog.cancel_button_text = "Cancel"
	
	# Add JSON button and get reference
	var json_button = dialog.add_button("JSON", 0)
	
	# Make buttons bigger
	dialog.get_ok_button().custom_minimum_size = Vector2(100, 50)
	dialog.get_cancel_button().custom_minimum_size = Vector2(100, 50)
	json_button.custom_minimum_size = Vector2(100, 50)
	
	dialog.confirmed.connect(func():
		_export_as_txt()
		dialog.queue_free()
	)
	
	json_button.pressed.connect(func():
		_export_as_json()
		dialog.queue_free()
	)
	
	dialog.canceled.connect(func():
		dialog.queue_free()
	)
	
	add_child(dialog)
	dialog.popup_centered(Vector2i(350, 120))

func _export_as_txt():
	# Export the edited version of the book as TXT
	var export_text = ""
	var del_regex = RegEx.new()
	del_regex.compile("\\[rev_del\\].*?\\[/rev_del\\]")
	
	# Iterate through all chapters (1-22)
	for chapter_num in range(1, 23):
		if not book.chapters.has(chapter_num):
			continue
		var chapter_title = book.chapter_titles[chapter_num - 1] if chapter_num - 1 < book.chapter_titles.size() else ""
		
		export_text += "\n\n"
		export_text += "CHAPTER %d\n" % [chapter_num]
		export_text += chapter_title + "\n\n"
		
		var verses = book.chapters[chapter_num]
		for verse_idx in range(verses.size()):
			var verse_data = verses[verse_idx]
			if verse_data == null:
				continue
			var verse_num = verse_idx + 1
			var chapter_verse = "Chapter %d, Verse %d" % [chapter_num, verse_num]
			var verse_text = verse_data["text"]  # Extract text from verse dictionary
			
			# Check if there's an edited version
			if edited_verses.has(chapter_verse):
				verse_text = edited_verses[chapter_verse]
				
				# Convert to string if it's stored as something else
				if not verse_text is String:
					verse_text = str(verse_text)
				
				# Remove [rev_del] tags and their contents
				verse_text = del_regex.sub(verse_text, "", true)
				# Strip [rev_add] and [rev_mod] tags but keep their contents
				verse_text = verse_text.replace("[rev_add]", "").replace("[/rev_add]", "")
				verse_text = verse_text.replace("[rev_mod]", "").replace("[/rev_mod]", "")
				verse_text = verse_text.replace("  ", " ").strip_edges()
			
			export_text += "%d  %s\n" % [verse_num, verse_text]
	
	# Save to file
	pending_export_text = export_text
	pending_export_format = "txt"
	
	if OS.has_feature("web"):
		# For web, copy to clipboard and notify
		DisplayServer.clipboard_set(export_text)
		print("Exported to clipboard (web mode)")
	else:
		# Show file dialog for picking location
		if file_dialog:
			file_dialog.queue_free()
			file_dialog = null
		file_dialog = FileDialog.new()
		file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		file_dialog.filters = PackedStringArray(["*.txt ; Text Files"])
		file_dialog.title = "Export as TXT"
		file_dialog.current_file = "revelation_edited.txt"
		file_dialog.file_selected.connect(_on_export_file_selected)
		add_child(file_dialog)
		file_dialog.popup_centered(Vector2(800, 600))

func _export_as_json():
	# Export edited verses as JSON for sharing/importing
	var json_data = JSON.stringify(edited_verses)
	
	pending_export_text = json_data
	pending_export_format = "json"
	
	if OS.has_feature("web"):
		# For web, copy to clipboard and notify
		DisplayServer.clipboard_set(json_data)
		print("Exported to clipboard (web mode)")
	else:
		# Show file dialog for picking location
		if file_dialog:
			file_dialog.queue_free()
			file_dialog = null
		file_dialog = FileDialog.new()
		file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		file_dialog.filters = PackedStringArray(["*.json ; JSON Files"])
		file_dialog.title = "Export as JSON"
		file_dialog.current_file = "revelation_edits.json"
		file_dialog.file_selected.connect(_on_export_file_selected)
		add_child(file_dialog)
		file_dialog.popup_centered(Vector2(800, 600))

func _on_export_file_selected(path: String):
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(pending_export_text)
		file.close()
		print("Exported to: " + path)
	else:
		print("Failed to export to: " + path)

func _on_import_button_pressed():
	# Open file dialog to import edited verses
	if not file_dialog:
		file_dialog = FileDialog.new()
		file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		file_dialog.filters = PackedStringArray(["*.json ; JSON Files"])
		file_dialog.title = "Import Edits"
		file_dialog.file_selected.connect(_on_import_file_selected)
		add_child(file_dialog)
	else:
		# Reuse existing dialog but change mode
		file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		file_dialog.title = "Import Edits"
		file_dialog.filters = PackedStringArray(["*.json ; JSON Files"])
	file_dialog.popup_centered(Vector2(800, 600))

func _on_import_file_selected(path: String):
	var file = FileAccess.open(path, FileAccess.READ)
	if file:
		var content = file.get_as_text()
		file.close()
		var data = JSON.parse_string(content)
		if data and typeof(data) == TYPE_DICTIONARY:
			edited_verses = data
			save_session_data()
			update_display()
			print("Imported edits from: " + path)
		else:
			print("Invalid JSON file format")
	else:
		print("Failed to open file: " + path)

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
