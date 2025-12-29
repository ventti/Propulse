# Project Instructions

## General Guidelines

- **Don't invent changes other than what's explicitly requested** - Only make changes that are directly asked for. Do not add "improvements", "fixes", or "optimizations" unless explicitly requested.

## AI Coding Rules

### Prime Directive

Prefer global correctness and maintainability over local optimization.
When context is missing, choose minimal, conservative changes.

### Scope & Changes

- Make the smallest change possible.
- Do not mix refactors and behavior changes.
- Split large or cross-cutting changes into stages.
- Do not leave partial refactors or TODO shims.

### Architecture & Invariants

- Assume architectural rules exist.
- Do not cross layers or break invariants.
- Preserve threading, ownership, error handling, and security rules.
- If unclear, stop and ask.

### Reuse & Consistency

- Search for and reuse existing code first.
- Do not introduce parallel implementations.
- Match existing naming, structure, and patterns exactly.
- Do not "improve style" unless asked.

### Dependencies & Compatibility

- Do not add dependencies unless explicitly allowed.
- Assume API/ABI and data formats are stable.
- Flag any compatibility-impacting changes.

### Testing

- All behavior changes require tests.
- Tests must encode invariants, not just happy paths.
- High-risk code requires stronger test coverage.

### Refactoring

- Refactors must be mechanical and behavior-preserving.
- Complete migrations fully or do not start them.

### Documentation & Review

- Document intent and assumptions, not obvious code.
- PRs must explain scope, invariants, and risks.
- Be ready to justify decisions.
- When mouse actions or keyboard shortcuts are added/removed/changed, update `data/help.txt` accordingly. Ensure the help text is up to date and does not contradict existing related functionality.

### Stop Conditions

Stop and ask if:
- Architecture or invariants are unclear.
- Multiple valid designs exist.
- Changes may affect unseen code.

### Forbidden

- Speculative abstractions
- Hidden behavior changes
- Style-only rewrites
- Guessing system-wide rules

**Principle: Act as a careful maintainer, not a rewriter.**

## Development Principles

Prefer these principles when writing and modifying code:

- **DRY (Don't Repeat Yourself)** - Avoid code duplication. Extract common logic into reusable functions, procedures, or units. If similar code appears in multiple places, refactor it into a shared implementation.
- **KISS (Keep It Simple, Stupid)** - Prefer simple, straightforward solutions over complex ones. Write code that is easy to understand and maintain. Avoid unnecessary abstractions or over-engineering.
- **YAGNI (You Aren't Gonna Need It)** - Don't add functionality until it's actually needed. Avoid speculative features, premature optimizations, or "just in case" code. Focus on solving the current problem.

## Commit Message Conventions

When making commits (especially when the AI agent generates commit messages), follow these rules:

### Format Rules

1. **Use lowercase** - All commit messages should be in lowercase
2. **Present tense imperative** - Use verbs like "add", "fix", "update", "improve", "extend", "toggle", "remove", "refactor", "enable", "disable", etc.
3. **Be concise and descriptive** - Clearly describe what the commit does, focusing on the main change or purpose
4. **No period at the end** - Do not end commit messages with a period
5. **Optional colon for detail** - Use a colon to add detail when helpful (e.g., "improve orderlist: show dots for unused entries and auto-expand on input")

### AI Agent Commit Message Generation

When the AI agent generates commit messages:

1. **Analyze the changes** - Review `git diff` or `git status` to understand what files were modified and what the changes accomplish
2. **Identify the main purpose** - Determine the primary effect or purpose of the changes (e.g., "add feature X", "fix bug Y", "improve Z")
3. **Use appropriate verb** - Choose a verb that accurately describes the action:
   - `add` - for new features, files, or functionality
   - `fix` - for bug fixes or corrections
   - `update` - for version bumps, dependency updates, or modifications to existing features
   - `improve` - for enhancements or optimizations
   - `extend` - for adding to existing functionality
   - `refactor` - for code restructuring without changing behavior
   - `remove` - for deleting features or code
   - `enable`/`disable` - for feature flags or build options
   - `toggle` - for switching between states
4. **Be specific** - Include the component or area affected (e.g., "pattern editor", "orderlist", "sample editor", "Makefile")
5. **Add detail when needed** - Use a colon to provide additional context if the main message needs clarification

### Examples

Good commit messages:
- `add undo/redo system to sample editor`
- `toggle volume and effect editing together with comma key`
- `extend undo/redo to orderlist and restore cursor position`
- `improve orderlist: show dots for unused entries and auto-expand on input`
- `fix soxr detection on macOS by preventing automatic disable`
- `update version to 0.10.0 and change URL to github`
- `remove windows-x86 and linux-x86 support`
- `add null checks and exception handling for module operations`
- `refactor autosave interval to unified data structure`
- `fix autosave conditions and refactor interval checking`

Bad commit messages:
- `Added undo/redo system` (wrong tense, capitalized)
- `Fixed bug.` (capitalized, has period)
- `Update Makefile` (too vague)
- `Changes` (not descriptive)
- `Fixed stuff` (too vague, capitalized)

## Code Style

- Follow Pascal/FreePascal conventions
- Use consistent indentation (spaces or tabs as per existing code)
- Comment complex logic
- Keep functions focused and reasonably sized

## Pascal/FPC build safety (avoid known ICE patterns)

- Prefer **a single `const` block** for related constants; avoid consecutive `const` sections in the same unit (workaround for FPC internal compiler errors seen in cross-compilation).
- If cross-compiling fails with an **FPC internal error**, try the smallest syntax reshapes first (reorder constants, merge sections, avoid unusual literal forms) before larger refactors.

## File Organization

- Source files in `src/`
- Documentation in `docs/`
- Build artifacts should not be committed (see `.gitignore`)
- Libraries in `lib/` are committed despite `.gitignore` (as per project requirements)

## Atomic Commits

- Make atomic commits - one logical change per commit
- Split large changes into multiple commits when appropriate
- Group related changes together
- Follow the existing commit style in the repository

See `COMMIT_CONVENTIONS.md` for more details.



## Playback shortcuts + cursor positioning (investigation pointers)

- **Shortcut entry points**:
  - Global keys are bound and dispatched in `src/mainwindow.pas` (`Shortcuts.Bind(...)`, `TWindow.OnKeyDown`)
  - Screen-/control-specific handling may live in the relevant `src/screen/*.pas` unit (`KeyDown(...)`)

- **Two positions exist while playing**:
  - The *playback position* is tracked by the module player (`Module.PlayPos` / `TPTModule.PlayPos`)
  - The *edit cursor position* is tracked by UI controls (e.g. `PatternEditor.Cursor`, `OrderList.Cursor`)
  - `FollowPlayback` affects *view following* (scroll/pattern) and should not be assumed to move the edit cursor

- **How playback position updates reach the UI**:
  - The player posts SDL user events (e.g. row/order change) via `PostMessagePtr(...)` (`src/protracker/protracker.messaging.pas`)
  - The main loop handles those events in `src/mainwindow.pas` and refreshes UI (`UpdatePatternView`, `ModuleOrderChanged`)

- **User-facing help text**: `data/help.txt` (loaded by `src/screen/screen.help.pas`)

