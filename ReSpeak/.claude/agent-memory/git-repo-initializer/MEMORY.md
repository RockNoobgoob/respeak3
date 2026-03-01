# Git Repo Initializer - Agent Memory

## Project Git Structure

- Git root is C:\Users\noah\ReSpeak3 (one level ABOVE the ReSpeak project folder)
- The ReSpeak project lives at C:\Users\noah\ReSpeak3\ReSpeak (a subfolder inside the repo)
- All git commands must target C:\Users\noah\ReSpeak3 or use -C with the project path
- The .gitignore lives at C:\Users\noah\ReSpeak3\ReSpeak\.gitignore and scopes to that subfolder

## Initial Commit

- Commit hash: e87217efe6d7069b8ecb9676c59b36e826999d7b
- Message: "Initial Xcode project scaffold"
- Branch: main
- 15 files committed

## Files Intentionally Not Tracked

- ../.claude/ (parent-level claude directory, outside project scope)
- .claude/settings.local.json (local IDE settings, should not be committed)
- These appear as untracked in git status but are correctly excluded

## Windows-Specific Notes

- CRLF warnings on git add are expected and harmless on Windows
- Use Unix-style paths (/c/Users/...) in bash commands even on Windows
