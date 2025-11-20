# Commit Message Conventions

This document describes the commit message conventions used in this repository.

## Format

- **Lowercase**: All commit messages should be in lowercase
- **Present tense imperative**: Use verbs like "add", "fix", "update", "improve", "extend", "toggle", "remove", etc.
- **Concise and descriptive**: Be clear about what the commit does
- **No period**: Do not end commit messages with a period
- **Optional colon**: Use a colon to add detail when helpful (e.g., "improve orderlist: show dots...")

## Examples

Good commit messages:
```
add undo/redo system to sample editor
toggle volume and effect editing together with comma key
extend undo/redo to orderlist and restore cursor position
improve orderlist: show dots for unused entries and auto-expand on input
fix soxr detection on macOS by preventing automatic disable
update version to 0.10.0 and change URL to github
remove windows-x86 and linux-x86 support
```

Bad commit messages:
```
Added undo/redo system  (wrong tense, capitalized)
Fixed bug.  (capitalized, has period)
Update Makefile  (too vague)
```

## Git Configuration

To use the commit message template, configure git:

```bash
git config commit.template .gitmessage
```

Or set it globally:

```bash
git config --global commit.template .gitmessage
```

