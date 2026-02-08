# commit

Create atomic commits for the current worktree changes.

## Objective
- Group related changes into minimal, logical commits.
- Use Conventional Commits with a one-line subject that explains why.

## Requirements
- Never commit `dist/*` or generated artifacts unless explicitly requested.
- If unrelated changes exist, leave them unstaged.
- Ask for confirmation if the commit grouping is ambiguous.
- Observe if the staged changes contain multiple logical changes. If yes, split the staged changes to multiple commits.

## Output
- A short list of planned commits (1–4 items).
- For each commit: files to include and a proposed message.
- Then perform the commits if the user approves.
