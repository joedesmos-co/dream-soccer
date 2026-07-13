# Dream Soccer Development Workflow

## Core rule

Build only one gameplay milestone at a time.

Never begin the next milestone if:
- the project does not parse
- the main scene does not load
- existing validation fails
- a working feature has regressed
- manual testing is still required for a serious issue

## Protected working systems

The following systems currently work and must not be rewritten without explicit approval:

- Broadcast camera
- Keyboard and controller movement
- Sprint
- Player-side possession acquisition
- Simple possessed-ball controller
- Preferred-foot ball offset
- Existing collision layers and collision exceptions
- Camera zoom clamp

Extend these systems through small interfaces. Do not replace or broadly refactor them.

## Required process for every milestone

1. Read:
   - PROJECT_RULES.md
   - DEVELOPMENT_WORKFLOW.md
   - current relevant scenes and scripts

2. Inspect the existing implementation before editing.

3. Write a brief implementation plan.

4. Identify:
   - files expected to change
   - existing systems that must remain untouched
   - regression risks
   - manual tests required

5. Implement only the requested milestone.

6. Run:
   - Godot import or validation
   - script parsing
   - main scene instantiation
   - any available automated tests

7. Perform a regression audit covering:
   - movement
   - sprint
   - camera
   - possession acquisition
   - dribbling
   - collision behavior
   - controller bindings

8. Fix all errors caused by the milestone.

9. Stop and report if validation cannot pass.

10. Provide:
   - changed files
   - design explanation
   - validation results
   - known limitations
   - exact manual test checklist

Do not claim gameplay feel is correct without manual testing.

## Version-control rule

Do not commit automatically unless explicitly instructed.

Each completed and manually approved milestone receives its own commit.