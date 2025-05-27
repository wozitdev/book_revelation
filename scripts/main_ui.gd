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
	"last_position": {"chapter": 0, "verse": 0},
	"expanded_chapters": {}  # Will be populated with proper keys
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
		# Ensure the saved position is valid
		if not book.navigate_to(session_data.last_position.chapter, session_data.last_position.verse):
			# If navigation fails, reset to first verse
			session_data.last_position.chapter = 0
			session_data.last_position.verse = 0
			book.navigate_to(0, 0)
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
		previous_button.pressed.connect(_on_previous_button_pressed)
		next_button.pressed.connect(_on_next_button_pressed)
		search_input.text_changed.connect(_on_search_input_text_changed)
		search_clear_button.pressed.connect(_on_clear_search_pressed)
		
		# Setup text editors
		text_display.editable = false
		text_display.add_theme_color_override("font_color", Color(1, 1, 1))
		
		edited_text_display.editable = true
		edited_text_display.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY

func setup_search_timer():
	search_timer = Timer.new()
	search_timer.wait_time = 0.3
	search_timer.one_shot = true
	search_timer.timeout.connect(_perform_search)
	add_child(search_timer)

func load_session_data():
	# Initialize with default values first
	session_data = {
		"last_position": {"chapter": 0, "verse": 0},
		"expanded_chapters": {}
	}
	
	var file = FileAccess.open("user://session_data.json", FileAccess.READ)
	if file:
		var data = JSON.parse_string(file.get_as_text())
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

func save_session_data():
	# Convert integer keys to strings for JSON compatibility
	var save_data = {
		"last_position": session_data.last_position,
		"expanded_chapters": {}
	}
	
	for chapter_index in session_data.expanded_chapters:
		save_data.expanded_chapters[str(chapter_index)] = session_data.expanded_chapters[chapter_index]
	
	var file = FileAccess.open("user://session_data.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_data))
		file.close()

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
	if book.navigate_to(chapter, verse):
		session_data.last_position.chapter = chapter
		session_data.last_position.verse = verse
		save_session_data()
		
		update_display()
		update_toc_selection(chapter, verse)
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
			chapter_header.text = "*" + chapter_text
		else:
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
			
			verse_button.custom_minimum_size = Vector2(30, 30)
			verse_button.pressed.connect(_on_verse_button_pressed.bind(chapter_index, verse))
			
			# Highlight current verse
			if chapter_index == book.current_chapter and verse == book.current_verse:
				verse_button.add_theme_color_override("font_color", Color(0.3, 0.7, 1.0))
			
			verse_grid.add_child(verse_button)
		
		toc_container.add_child(chapter_section)

func _on_chapter_header_pressed(chapter: int):
	# Prevent collapsing the currently selected chapter
	if chapter == book.current_chapter:
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
	
	chapter_verse_label.text = chapter_verse
	update_toc_selection(book.current_chapter, book.current_verse)
	
	update_toc_edit_indicators()
	apply_search_highlighting()

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
					session_data.expanded_chapters[chapter] = true
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