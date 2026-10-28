# Wiki archive

> [!WARNING]
> **Don't use these pages as documentation.** Earlier agent sessions wrote them during the proof of concept, and much of what they say doesn't match the code: they describe files that don't exist, a key setup that was removed in 1.3.0, and a database migration the app never uses. For current docs, see [`docs/`](../../README.md).

This is a snapshot of the project's GitHub wiki, taken from wiki commit `5ac096e` (2026-06-04) when the wiki was retired (#6). It's kept as an input for planning: the ideas and the history in it are worth having to hand during the design review.

The pages are verbatim with one exception: an NS API key in `API_SECURITY_SETUP.md` is replaced with `<redacted>`. That key was rotated on 2026-10-28 and no longer works. Links in the `[[PAGE]]` form are wiki syntax and don't resolve here; the pages they name are the files in this folder.

| Page | What it covered |
|---|---|
| [Home](Home.md) | The wiki's index |
| [QUICK_START](QUICK_START.md) | Getting from a clone to a running app |
| [API_SECURITY_SETUP](API_SECURITY_SETUP.md) | Configuring the NS API key through `Secrets.xcconfig` |
| [BACKEND_ARCHITECTURE](BACKEND_ARCHITECTURE.md) | The backend layer |
| [ARCHITECTURE_DIAGRAMS](ARCHITECTURE_DIAGRAMS.md) | Diagrams of the system |
| [BACKEND_REVIEW](BACKEND_REVIEW.md) | An earlier review of the backend code |
| [DATABASE_MIGRATION_FINAL](DATABASE_MIGRATION_FINAL.md) | The visited-stations schema migration |
| [QUICK_DATABASE_FIX](QUICK_DATABASE_FIX.md) | Recovering from database errors |
