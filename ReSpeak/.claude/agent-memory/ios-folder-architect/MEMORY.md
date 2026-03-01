# iOS Folder Architect — Agent Memory

## Project Identity
- Target name: ReSpeak
- Scheme name: ReSpeak
- Bundle ID: com.hovarehab.respeak
- Source root: ReSpeak/ (relative to project root C:/Users/noah/ReSpeak3/ReSpeak/)
- Xcodeproj: C:/Users/noah/ReSpeak3/ReSpeak/ReSpeak.xcodeproj
- No .xcworkspace (no CocoaPods / SPM workspace wrapper)
- Deployment target: iOS 16.0, Swift 5.0, Xcode 14 compatibility version

## Architecture Folder Setup — Completed 2026-03-01
Canonical structure established. See details/uuid-map.md for UUID assignments.

## Environment Notes
- Development machine: Windows 11 (Git Bash / MINGW64)
- xcodebuild is NOT available on this machine — builds must be verified on macOS
- UUID validation was performed with Node.js (node is available, python3 is not)
- pbxproj edited directly (no xcodeproj Ruby gem available on Windows)

## pbxproj Editing Rules (Windows — no xcodeproj gem)
- Edit project.pbxproj directly as text
- UUID format: 24 uppercase hex chars (e.g., AA100001000000000000AA00)
- sourceTree = "<group>" for all source groups/files; path is relative to parent group
- After edits, validate with Node.js: every UUID referenced must be defined as a key
- See details/uuid-map.md for the current UUID registry

## Safety Rules Confirmed Working
- Never use virtual groups — all groups have a matching path= key pointing to a real folder
- Moved files keep their original PBXFileReference UUID; only the parent group changes
- Build phase membership (PBXBuildFile) UUIDs are separate from PBXFileReference UUIDs
