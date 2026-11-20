#!/bin/bash
TARGET_DIR="/Users/adityagiri/Library/Developer/Xcode/UntitledProjects/Untitled Project/MyApp/SptTerm"
SOURCE_DIR="/Users/adityagiri/Documents/sptterm/SptTerm"

rsync -av --delete "$SOURCE_DIR/" "$TARGET_DIR/"
echo "Sync complete."
