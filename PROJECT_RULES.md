Dream Soccer Project Rules

Project vision

Dream Soccer is intended to become a cross-platform, live-service soccer game with full matches, career modes, short competitive modes, seasonal squad building, permanent account Prestige, lifetime statistics, and archived collectible cards.

That is the long-term vision only. Do not attempt to build the full game yet.

Current milestone

Build a small offline 3D soccer prototype containing:

* One controllable player
* One soccer ball
* One small field
* Two goals
* Basic movement
* Basic ball interaction
* Passing and shooting
* Goal detection
* A score display
* Ball and player reset after goals

Technical rules

* Use Godot 4.
* Use typed GDScript.
* Use modular scenes and scripts.
* Use placeholder geometry before custom artwork.
* Keep systems small and understandable.
* Do not add unnecessary dependencies or plugins.
* Do not use copyrighted club badges, player photographs, kits, or league branding.
* Do not add online multiplayer yet.
* Do not add accounts, cards, packs, monetization, Career Mode, or live-service features yet.
* Do not make sweeping rewrites unless specifically requested.
* Preserve working features when adding new ones.
* Inspect existing files before changing them.
* Explain major architectural decisions.
* Run available validation checks after changes.
* Report any feature that could not be tested automatically.

Development workflow

For each task:

1. Inspect the project.
2. Explain the proposed approach.
3. Implement only the requested milestone.
4. Check scripts for parser errors.
5. Run the project or available headless validation.
6. Summarize changed files.
7. List manual testing steps.
8. Commit only after the user confirms the feature works.