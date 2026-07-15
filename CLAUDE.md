# CLAUDE.md

Instructions for Claude Code when working in this repository.

## Never build or run the app

Never run `xcodebuild`, or any other command that compiles this project.
Never open Xcode or launch the iOS Simulator for this project, for any
reason — including "just to verify it compiles." The user builds and runs
the app themselves by pressing Play in Xcode. If you need to sanity-check a
change, read the code carefully instead; do not invoke the build system.

`xcodegen generate` is the one exception — it's fine to run. It only
regenerates `RoastMyGallery.xcodeproj` from `project.yml` (project-file
bookkeeping: which files belong to which target), it does not compile
anything or launch anything. Run it whenever you add or remove a Swift file
so Xcode's project navigator picks up the change — editing an existing
file's contents never requires it.
