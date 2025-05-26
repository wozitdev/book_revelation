# Book of Revelation Reader

A Godot-based application for reading and navigating through the Book of Revelation.

## Project Overview

This application provides an interactive interface for reading the Book of Revelation, with features including:
- Verse-by-verse navigation
- Chapter and verse tracking
- Clean, readable text display
- Responsive layout

## Technical Details

- Built with Godot 4.4
- Uses GDScript for functionality
- Scene-based architecture

## Project Structure

```
book_revelation/
├── scenes/
│   └── main.tscn         # Main scene with UI layout
├── scripts/
│   ├── book.gd          # Book text handling and navigation logic
│   └── main_ui.gd       # UI interaction handling
├── resources/           # Resource files
└── Revelation.txt      # Source text file
```

## Development Setup

1. Ensure you have Godot 4.4 or later installed
2. Clone this repository
3. Open the project in Godot
4. Run the main scene (scenes/main.tscn)

## Components

### Book Handler (book.gd)
- Manages the loading and parsing of the Revelation text
- Handles verse navigation
- Maintains current chapter and verse state

### UI Controller (main_ui.gd)
- Controls the display of text
- Manages navigation buttons
- Updates chapter/verse labels
