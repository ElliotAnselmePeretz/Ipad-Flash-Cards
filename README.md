# Ipad-Flash-Cards

A handwriting flashcard app for iPad. Write your answers with Apple Pencil; cards come
back just before you'd forget them, using the spaced-repetition algorithm Anki ran on
for fifteen years.

## Status

| Layer | State |
|---|---|
| `FlashcardsCore` — scheduling, models, queue | **Written and verified.** 52 assertions pass, including a 200-learner one-year simulation. |
| `App/` — SwiftUI, PencilKit, SwiftData | **Written but not yet compiled.** Needs Xcode and the iOS SDK. |

The split is deliberate: the core is pure Swift with no UI or persistence framework
attached, so the algorithm can be tested on any machine with a Swift toolchain. The app
layer is a thin shell over it.

## Verifying the core

This machine has Command Line Tools but not Xcode, and its SwiftPM is broken
(`libPackageDescription.dylib` doesn't match its `.swiftmodule`), so the validation
harness compiles directly:

```bash
cd FlashcardsCore && swiftc -O -o .build/validate $(find Sources -name '*.swift') Validation/main.swift && ./.build/validate
```

`Tests/FlashcardsCoreTests` holds the equivalent XCTest suite for once Xcode is installed;
`Validation/` mirrors it so the logic can be checked without Xcode, and stays useful for CI.

## Building the app

1. Install Xcode from the Mac App Store.
2. Create an iPad app target and add `FlashcardsCore` as a local package dependency.
3. Add the files under `App/` to the target.
4. Deployment target iOS 17 or later (SwiftData and `@Observable` both require it).

Free Apple IDs can sideload, but builds expire after seven days and cannot use iCloud.
A paid Apple Developer membership ($99/yr) removes both limits.

## Scheduling

`SM2Scheduler` implements the SM-2 variant Anki used, with Anki's default settings:

- **New cards** step through 1 minute, then 10 minutes, then graduate to a 1-day interval.
  `Easy` on a new card skips straight to 4 days.
- **Review cards** multiply their interval by an ease factor that starts at 2.5 and drifts
  with your answers (`Hard` −0.15, `Easy` +0.15, a lapse −0.20, floor 1.3).
- **Lapses** reset the interval and send the card through a 10-minute relearning step.
- **Interval fuzz** of ±5% stops a batch of cards learned together from coming due
  together forever. Intervals under two days are left exact.

Everything is tunable through `SchedulerConfig`, per profile and per deck.

Swapping in FSRS later means replacing one function. `ReviewLog` deliberately records the
before-and-after state of every answer, so the full history can be replayed against a new
algorithm rather than thrown away.

## Multi-user

Every deck, card and review log carries a `profileID`. Several people can share one iPad
with separate decks, schedules and statistics.

The models are also shaped for sync that doesn't exist yet: UUID primary keys, `modifiedAt`
on every record, and soft deletes (`deletedAt`) rather than hard ones. Turning on CloudKit
is then a one-line change in `FlashcardsApp.swift` — `cloudKitDatabase: .automatic` — with
no migration. Private-database data counts against each user's own iCloud quota, so sync
costs the developer nothing beyond the membership.

## Layout

```
FlashcardsCore/
  Sources/FlashcardsCore/
    Scheduling/    SM2Scheduler, SchedulingState, SchedulerConfig, ReviewGrade, ReviewQueue
    Models/        Profile, Deck, Card, ReviewLog
  Tests/           XCTest suite (needs Xcode)
  Validation/      standalone harness (runs on the CLI today)
App/
  FlashcardsApp.swift      entry point, ModelContainer, profile gate
  Persistence/             SwiftData models, flattened scheduling for #Predicate
  Services/StudySession    queue state, grading, review logging, daily limits
  Views/                   profile picker, deck list, study screen, card editor, stats
```

## Known gaps

- The app layer has never been compiled; expect the usual first-build fixes.
- No deck import/export yet (Anki `.apkg` or CSV).
- Handwriting is self-graded — no recognition, by design.
- The XCTest suite duplicates the CLI harness; collapse them once Xcode is available.
