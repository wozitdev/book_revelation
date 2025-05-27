extends Node

var chapters = []
var current_chapter = 0
var current_verse = 0
var verse_index = {}  # Store indexed terms and their references
var current_chapter_verse = ""

# Store chapter titles/summaries for TOC
var chapter_titles = [
	"The Vision of Christ and Letters to Seven Churches",
	"Messages to Ephesus, Smyrna, Pergamos, and Thyatira",
	"Messages to Sardis, Philadelphia, and Laodicea",
	"The Throne Room Vision and the Scroll",
	"The Seven Seals",
	"The 144,000 and the Great Multitude",
	"The Seven Trumpets Begin",
	"The Seven Trumpets Continue",
	"The Angel and the Little Scroll",
	"The Two Witnesses",
	"The Woman and the Dragon",
	"The Beast from the Sea and Earth",
	"The Lamb and His Followers",
	"The Angels' Proclamations",
	"The Seven Bowl Judgments Prepared",
	"The Seven Bowls of God's Wrath",
	"The Great Prostitute on the Beast",
	"The Fall of Babylon the Great",
	"The Return of Christ",
	"The Thousand Year Reign",
	"The New Heaven and New Earth",
	"The New Jerusalem"
]

func _ready():
	load_text()
	build_verse_index()

func load_text():
	var file = FileAccess.open("res://Revelation.txt", FileAccess.READ)
	if file:
		parse_file(file)
		file.close()

func parse_file(file: FileAccess):
	var current_verses = []
	var last_chapter = "0"
	var current_verse_info = null
	var current_verse_text = ""
	
	while !file.eof_reached():
		var line = file.get_line().strip_edges()
		if line.is_empty():
			continue
			
		if line.begins_with("66:"):
			# New verse starts
			if current_verse_info != null:
				current_verses.append({
					"verse": current_verse_info["verse"],
					"text": current_verse_text.strip_edges()
				})
			
			var parts = line.split(":")
			var chapter = parts[1].to_int()
			var verse = parts[2].split(" ")[0].to_int() - 1
			current_verse_text = line.substr(line.find(" ") + 1)
			current_verse_info = {"verse": verse}
			
			if str(chapter) != last_chapter:
				if !current_verses.is_empty():
					chapters.append(current_verses)
				current_verses = []
				last_chapter = str(chapter)
		else:
			# Continue previous verse
			current_verse_text += " " + line
	
	# Don't forget to add the last verse and chapter
	if current_verse_info != null:
		current_verses.append({
			"verse": current_verse_info["verse"],
			"text": current_verse_text.strip_edges()
		})
	if !current_verses.is_empty():
		chapters.append(current_verses)

func build_verse_index():
	verse_index.clear()
	for chapter_idx in range(chapters.size()):
		for verse_idx in range(chapters[chapter_idx].size()):
			var verse_text = chapters[chapter_idx][verse_idx]["text"]
			index_verse(verse_text, chapter_idx, verse_idx)

func clean_word(word: String) -> String:
	# Remove common punctuation and convert to lowercase
	var cleaned = word.to_lower()
	cleaned = cleaned.replace(",", "")
	cleaned = cleaned.replace(".", "")
	cleaned = cleaned.replace(";", "")
	cleaned = cleaned.replace(":", "")
	cleaned = cleaned.replace("!", "")
	cleaned = cleaned.replace("?", "")
	cleaned = cleaned.replace("\"", "")
	return cleaned.strip_edges()

func index_verse(text: String, chapter: int, verse: int):
	# Index individual words
	var words = text.split(" ")
	for i in range(words.size()):
		var word = clean_word(words[i])
		if word.length() < 2:  # Allow shorter words but still skip single letters
			continue
			
		if !verse_index.has(word):
			verse_index[word] = []
		
		var ref = {
			"chapter": chapter,
			"verse": verse,
			"position": i,
			"preview": text.substr(0, min(200, text.length()))
		}
		verse_index[word].append(ref)

func search_index(query: String) -> Array:
	var results = []
	var words = query.to_lower().split(" ")
	var matches = {}
	
	for word in words:
		if verse_index.has(word):
			for result in verse_index[word]:
				var key = "%d:%d" % [result["chapter"], result["verse"]]
				if !matches.has(key):
					matches[key] = result
	
	for match in matches.values():
		results.append(match)
	
	return results

func fuzzy_search(query: String) -> Array:
	if query.length() < 2:
		return []
	
	var results = []
	var query_lower = query.to_lower()
	var query_words = query_lower.split(" ")
	
	# Score-based fuzzy matching
	for chapter_idx in range(chapters.size()):
		for verse_idx in range(chapters[chapter_idx].size()):
			var verse_text = chapters[chapter_idx][verse_idx]["text"]
			var verse_lower = verse_text.to_lower()
			var score = 0
			var match_count = 0
			
			# Check for exact phrase match (highest score)
			if verse_lower.find(query_lower) != -1:
				score += 100
				match_count += 1
			
			# Check for individual word matches
			for word in query_words:
				if word.length() >= 2:
					if verse_lower.find(word) != -1:
						score += 10
						match_count += 1
					else:
						# Fuzzy matching for similar words
						var verse_words = verse_lower.split(" ")
						for verse_word in verse_words:
							var clean_verse_word = clean_word(verse_word)
							if clean_verse_word.length() >= 2:
								var similarity = calculate_similarity(word, clean_verse_word)
								if similarity > 0.7:  # 70% similarity threshold
									score += int(similarity * 5)
									match_count += 1
									break
			
			# Only include results with at least one match
			if match_count > 0:
				# Create preview with highlighted terms
				var preview = verse_text
				if preview.length() > 150:
					var start_pos = max(0, verse_lower.find(query_lower) - 50)
					preview = "..." + preview.substr(start_pos, 150) + "..."
				
				results.append({
					"chapter": chapter_idx,
					"verse": verse_idx,
					"score": score,
					"preview": preview,
					"match_count": match_count
				})
	
	# Sort by score (highest first), then by match count
	results.sort_custom(func(a, b): 
		if a["score"] != b["score"]:
			return a["score"] > b["score"]
		return a["match_count"] > b["match_count"]
	)
	
	# Return top 100 results
	return results.slice(0, min(100, results.size()))

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

func get_current_text() -> String:
	if current_chapter < chapters.size() and current_verse < chapters[current_chapter].size():
		return chapters[current_chapter][current_verse]["text"]
	return ""

func get_chapter_verse() -> String:
	return "Chapter %d, Verse %d" % [current_chapter + 1, current_verse + 1]

func navigate_to(chapter: int, verse: int) -> bool:
	if chapter < 0 or chapter >= chapters.size():
		return false
	if verse < 0 or verse >= chapters[chapter].size():
		return false
	
	current_chapter = chapter
	current_verse = verse
	return true

func next_verse() -> bool:
	if current_verse + 1 < chapters[current_chapter].size():
		current_verse += 1
		return true
	elif current_chapter + 1 < chapters.size():
		current_chapter += 1
		current_verse = 0
		return true
	return false

func previous_verse() -> bool:
	if current_verse > 0:
		current_verse -= 1
		return true
	elif current_chapter > 0:
		current_chapter -= 1
		current_verse = chapters[current_chapter].size() - 1
		return true
	return false

func get_toc_data() -> Array:
	var data = []
	for i in range(chapters.size()):
		data.append({
			"chapter": i + 1,
			"verse_count": chapters[i].size(),
			"title": chapter_titles[i] if i < chapter_titles.size() else "Chapter " + str(i + 1)
		})
	return data

func clear_edit(chapter_verse: String):
	# Load edited verses
	var save_file = FileAccess.open("user://edited_verses.json", FileAccess.READ)
	if save_file:
		var data = JSON.parse_string(save_file.get_as_text())
		save_file.close()
		if data and data.has(chapter_verse):
			# Remove the edit
			data.erase(chapter_verse)
			# Save back to file
			save_file = FileAccess.open("user://edited_verses.json", FileAccess.WRITE)
			if save_file:
				save_file.store_string(JSON.stringify(data))
				save_file.close()
				print("Cleared edit for " + chapter_verse)
			else:
				print("Error: Could not save after clearing edit")

func load_verse(chapter: String, verse: String) -> String:
	current_chapter_verse = chapter + ":" + verse
	return get_verse_text(current_chapter_verse)

func get_verse_text(chapter_verse: String) -> String:
	# First check if there's an edited version
	var edited_text = load_edited_verse(chapter_verse)
	if edited_text != "":
		return edited_text
	
	# Otherwise return the original text
	return get_original_verse_text(chapter_verse)

func load_edited_verse(chapter_verse: String) -> String:
	var save_file = FileAccess.open("user://edited_verses.json", FileAccess.READ)
	if save_file:
		var data = JSON.parse_string(save_file.get_as_text())
		save_file.close()
		if data and data.has(chapter_verse):
			return data[chapter_verse]
	return ""

func get_original_verse_text(chapter_verse: String) -> String:
	# Original implementation for getting verse text from Revelation.txt
	var parts = chapter_verse.split(":")
	var chapter = parts[0].to_int() - 1
	var verse = parts[1].to_int() - 1
	if chapter < chapters.size() and verse < chapters[chapter].size():
		return chapters[chapter][verse]["text"]
	return ""

func search_including_edits(query: String, edited_verses: Dictionary) -> Array:
	if query.length() < 2:
		return []
	
	var results = []
	var query_lower = query.to_lower()
	var query_words = query_lower.split(" ")
	
	# Score-based fuzzy matching
	for chapter_idx in range(chapters.size()):
		for verse_idx in range(chapters[chapter_idx].size()):
			var chapter_verse_key = "Chapter %d, Verse %d" % [chapter_idx + 1, verse_idx + 1]
			var verse_text = ""
			
			# Use edited version if available, otherwise use original
			if edited_verses.has(chapter_verse_key):
				verse_text = edited_verses[chapter_verse_key]
			else:
				verse_text = chapters[chapter_idx][verse_idx]["text"]
			
			var verse_lower = verse_text.to_lower()
			var score = 0
			var match_count = 0
			
			# Check for exact phrase match (highest score)
			if verse_lower.find(query_lower) != -1:
				score += 100
				match_count += 1
			
			# Check for individual word matches
			for word in query_words:
				if word.length() >= 2:
					if verse_lower.find(word) != -1:
						score += 10
						match_count += 1
					else:
						# Fuzzy matching for similar words
						var verse_words = verse_lower.split(" ")
						for verse_word in verse_words:
							var clean_verse_word = clean_word(verse_word)
							if clean_verse_word.length() >= 2:
								var similarity = calculate_similarity(word, clean_verse_word)
								if similarity > 0.7:  # 70% similarity threshold
									score += int(similarity * 5)
									match_count += 1
									break
			
			# Only include results with at least one match
			if match_count > 0:
				# Create preview with highlighted terms
				var preview = verse_text
				if preview.length() > 150:
					var start_pos = max(0, verse_lower.find(query_lower) - 50)
					preview = "..." + preview.substr(start_pos, 150) + "..."
				
				results.append({
					"chapter": chapter_idx,
					"verse": verse_idx,
					"score": score,
					"preview": preview,
					"match_count": match_count
				})
	
	# Sort by score (highest first), then by match count
	results.sort_custom(func(a, b): 
		if a["score"] != b["score"]:
			return a["score"] > b["score"]
		return a["match_count"] > b["match_count"]
	)
	
	# Return top 20 results
	return results.slice(0, min(20, results.size()))
