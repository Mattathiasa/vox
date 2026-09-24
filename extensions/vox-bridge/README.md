# Vox Bridge

A tiny extension for VS Code–based IDEs (Antigravity, Kiro, VS Code, Cursor) that lets
the Vox voice assistant:

- open N terminals split side by side (`Vox 1`, `Vox 2`, …)
- send text to a specific terminal (optionally pressing Enter)
- list / focus / close the terminals it opened

It listens on `127.0.0.1` only, on a random port, and requires a random token that it
writes (mode 0600) to `~/Library/Application Support/Vox/bridges/`. No dependencies.

Install: double-click `scripts/Install-IDE-Bridge.command` in the Vox repo, then reload
the IDE window.
