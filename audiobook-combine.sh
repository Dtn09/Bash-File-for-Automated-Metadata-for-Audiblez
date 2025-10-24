#!/bin/bash

# Audiobook Combiner with EPUB Metadata
# ==========================================

# Check for ffmpeg and unzip
if ! command -v ffmpeg &> /dev/null; then
    echo "ffmpeg not installed. Run: brew install ffmpeg"
    exit 1
fi

if ! command -v unzip &> /dev/null; then
    echo "unzip not installed"
    exit 1
fi

# Find EPUB file
EPUB_FILE=$(ls *.epub 2>/dev/null | head -1)

if [ -n "$EPUB_FILE" ]; then
    echo "Found EPUB: $EPUB_FILE"
    echo "Extracting metadata..."

    # Extract EPUB to temp folder
    mkdir -p temp_epub
    unzip -q "$EPUB_FILE" -d temp_epub

    # Find OPF file (contains metadata)
    OPF_FILE=$(find temp_epub -name "*.opf" | head -1)

    if [ -n "$OPF_FILE" ]; then
        # Extract metadata
        BOOK_TITLE=$(grep -o '<dc:title[^>]*>[^<]*</dc:title>' "$OPF_FILE" | sed 's/<[^>]*>//g' | head -1)
        AUTHOR=$(grep -o '<dc:creator[^>]*>[^<]*</dc:creator>' "$OPF_FILE" | sed 's/<[^>]*>//g' | head -1)
        YEAR=$(grep -o '<dc:date[^>]*>[^<]*</dc:date>' "$OPF_FILE" | sed 's/<[^>]*>//g' | sed 's/-.*//' | head -1)
        GENRE=$(grep -o '<dc:subject[^>]*>[^<]*</dc:subject>' "$OPF_FILE" | sed 's/<[^>]*>//g' | head -1)

        echo "Metadata extracted:"
        echo "   Title: $BOOK_TITLE"
        echo "   Author: $AUTHOR"
        echo "   Year: $YEAR"
        [ -n "$GENRE" ] && echo "   Genre: $GENRE"

        # Try to extract cover
        COVER_ID=$(grep -o 'content="[^"]*".*name="cover"' "$OPF_FILE" | sed 's/content="\([^"]*\)".*/\1/' | head -1)
        if [ -z "$COVER_ID" ]; then
            COVER_ID=$(grep -o 'name="cover".*content="[^"]*"' "$OPF_FILE" | sed 's/.*content="\([^"]*\)".*/\1/' | head -1)
        fi

        if [ -n "$COVER_ID" ]; then
            COVER_HREF=$(grep "id=\"$COVER_ID\"" "$OPF_FILE" | grep -o 'href="[^"]*"' | sed 's/href="\([^"]*\)".*/\1/')
            if [ -n "$COVER_HREF" ]; then
                COVER_PATH=$(find temp_epub -name "$(basename "$COVER_HREF")" | head -1)
                if [ -f "$COVER_PATH" ]; then
                    cp "$COVER_PATH" "./temp_cover.jpg"
                    COVER_FILE="./temp_cover.jpg"
                    echo "   Cover: Extracted"
                fi
            fi
        fi
    fi

    rm -rf temp_epub
    echo ""
else
    echo "No EPUB file found - will ask for metadata manually"
    echo ""
fi

# If no metadata from EPUB, ask manually
if [ -z "$BOOK_TITLE" ]; then
    read -p "Book Title: " BOOK_TITLE
    read -p "Author: " AUTHOR
    read -p "Year: " YEAR
    read -p "Genre: " GENRE
fi

# Find chapter files
echo "🔍 Looking for chapter files..."
CHAPTER_COUNT=$(ls *chapter*.wav 2>/dev/null | wc -l | tr -d ' ')

if [ "$CHAPTER_COUNT" -eq 0 ]; then
    echo "No files found matching: *chapter*.wav"
    [ -f temp_cover.jpg ] && rm temp_cover.jpg
    exit 1
fi

echo "Found $CHAPTER_COUNT chapter files"
echo ""

FILENAME="${BOOK_TITLE} - ${AUTHOR}.m4b"

echo "Processing audiobook..."
echo ""

# Step 1: Create numbered copies
echo "Step 1/4: Copying files..."
counter=1
for f in *chapter*.wav; do
    cp "$f" "temp_$(printf "%04d" $counter).wav"
    counter=$((counter + 1))
done
echo "Done"

# Step 2: Create file list
echo "Step 2/4: Creating file list..."
for f in temp_*.wav; do
    echo "file '$f'" >> list.txt
done
echo "Done"

# Step 3: Combine
echo "Step 3/4: Combining chapters..."
ffmpeg -f concat -safe 0 -i list.txt -c:a aac -b:a 64k temp_audio.m4b -loglevel error -stats
echo ""
echo "Done"

# Step 4: Add metadata (with or without cover)
echo "Step 4/4: Adding metadata..."

if [ -n "$COVER_FILE" ] && [ -f "$COVER_FILE" ]; then
    ffmpeg -i temp_audio.m4b -i "$COVER_FILE" -map 0 -map 1 -c copy \
      -disposition:v:0 attached_pic \
      -metadata title="$BOOK_TITLE" \
      -metadata artist="$AUTHOR" \
      -metadata author="$AUTHOR" \
      -metadata album="$BOOK_TITLE" \
      -metadata album_artist="$AUTHOR" \
      -metadata date="$YEAR" \
      -metadata genre="$GENRE" \
      "$FILENAME" -loglevel error
else
    ffmpeg -i temp_audio.m4b -c copy \
      -metadata title="$BOOK_TITLE" \
      -metadata artist="$AUTHOR" \
      -metadata author="$AUTHOR" \
      -metadata album="$BOOK_TITLE" \
      -metadata album_artist="$AUTHOR" \
      -metadata date="$YEAR" \
      -metadata genre="$GENRE" \
      "$FILENAME" -loglevel error
fi

# Cleanup
rm temp_*.wav list.txt temp_audio.m4b temp_cover.jpg 2>/dev/null

echo "Done"
echo ""
echo "=========================================="
echo "Complete!"
echo ""
echo "File: $FILENAME"

if [ -f "$FILENAME" ]; then
    FILE_SIZE=$(du -h "$FILENAME" | cut -f1)
    DURATION=$(ffmpeg -i "$FILENAME" 2>&1 | grep Duration | awk '{print $2}' | tr -d ,)
    echo "Chapters: $CHAPTER_COUNT"
    echo "Size: $FILE_SIZE"
    echo "Duration: $DURATION"
    [ -n "$COVER_FILE" ] && echo "Cover: Included"
fi

echo ""
echo "Enjoy your audiobook!"
echo "=========================================="