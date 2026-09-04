# Ink Recall

A handwriting flashcard app for iPad. Write your answers with Apple Pencil; cards come
back just before you'd forget them, using the spaced-repetition algorithm Anki ran on
for fifteen years.

## Status

| Layer | State |
|---|---|
| `FlashcardsCore` — scheduling, models, queue, CSV import | 48 unit tests passing |
| `App/` — SwiftUI, PencilKit, SwiftData | Builds and runs on device |
| On a real iPad | Running on an iPad Pro (M1). Palm rejection and Pencil feel confirmed by hand. |

The split is deliberate: the core is pure Swift with no UI or persistence framework
attached, so the algorithm can be tested anywhere in milliseconds. The app layer is a
thin shell over it, verified by UI tests that drive the real screens.

## Running it

```bash
open InkRecall.xcodeproj
```

Pick your iPad (or an iPad simulator) and press ▶. Deployment target is iOS 17.

To put it on a physical iPad: plug it in and tap Trust, enable Settings → Privacy &
Security → Developer Mode, add your Apple ID under Xcode → Settings → Accounts, then
trust the developer certificate under Settings → General → VPN & Device Management.
On a free Apple ID the build expires after seven days; a paid membership removes that.

## Tests

```bash
cd FlashcardsCore && swift test          # 48 unit tests, ~0.01s
```

There is no UI test suite. It was removed once the design settled: the screens changed
faster than the tests could be rewritten, and each run cost fifteen minutes. The unit
tests remain because the scheduler and CSV parser are where the real logic lives, and
they run in under a hundredth of a second.

`FlashcardsCore/Validation` mirrors the unit tests as a plain executable, for checking the
scheduler on a machine with no Xcode:

```bash
cd FlashcardsCore && swiftc -O -o .build/validate $(find Sources -name '*.swift') Validation/main.swift && ./.build/validate
```

## Studying

Look at the question, decide, reveal, and answer **Hard**, **Medium** or **Easy**. There is
no writing during review — writing happens when you make the card, which keeps a review to
a few seconds.

`Hard` maps to the scheduler's failure grade. SM-2 needs a "bring this back soon" signal,
and with three buttons this is the one that means it. The cost is that a card you got right
but found hard resets rather than growing slowly.

## Writing cards

**Rapid capture** (Cards → Write cards) is the handwriting-first path: write the question,
tap once, write the answer, tap once, and you are on a blank question again. The advance
button stays disabled until the canvas actually has strokes, so tapping through cannot
create empty cards.

Typing was removed from the editor entirely: cards are handwritten. Typed text only ever
arrives through CSV import, and an imported question is shown above the canvas as a
read-only caption.

**CSV import** (Cards → Import) defaults to *questions only*. Importing typed answers would
defeat the point of a Pencil deck, so the answers arrive blank and you write them. The
parser handles quoted fields containing commas and newlines, doubled quotes, BOM, and
comma/semicolon/tab files, and skips questions already in the deck.

Every canvas is `.pencilOnly`, which is what makes a resting palm safe: iPadOS routes all
non-Pencil touches away from the ink pipeline.

## Scheduling

`SM2Scheduler` implements the SM-2 variant Anki used, with Anki's defaults:

- **New cards** step through 1 minute, then 10 minutes, then graduate to a 1-day interval.
  `Easy` on a new card skips straight to 4 days.
- **Review cards** multiply their interval by an ease factor starting at 2.5 that drifts
  with your answers (`Hard` −0.15, `Easy` +0.15, a lapse −0.20, floor 1.3).
- **Lapses** reset the interval and send the card through a 10-minute relearning step.
- **Interval fuzz** of ±5% stops cards learned together from coming due together forever.

A misgrade can be undone from the study screen: the card's previous scheduling state is
restored and the review is deleted from history, so the statistics stay honest.

Swapping in FSRS later means replacing one function. `ReviewLog` records the before-and-after
state of every answer, so history can be replayed against a new algorithm.

## One user, no sign-in

The app opens straight into the decks. A `Profile` record is created silently on first
launch and every deck, card and review log is still scoped by `profileID` — invisible now,
but it means multiple users or CloudKit sync stay possible without a data migration.

The models are shaped for sync that doesn't exist yet: UUID primary keys, `modifiedAt` on
every record, and soft deletes. Turning on CloudKit is a one-line change in
`FlashcardsApp.swift` (`cloudKitDatabase: .automatic`) with no migration. Private-database
data counts against each user's own iCloud quota, so sync costs nothing beyond membership.

## Layout

```
FlashcardsCore/
  Sources/FlashcardsCore/
    Scheduling/   SM2Scheduler, SchedulingState, SchedulerConfig, ReviewGrade, ReviewQueue
    Models/       Profile, Deck, Card, ReviewLog
    Import/       CSVParser, CardImporter
  Tests/          48 unit tests
  Validation/     standalone harness, no Xcode required
App/
  FlashcardsApp.swift   entry point, ModelContainer, profile gate
  Persistence/          SwiftData models, sample deck
  Services/             StudySession — queue, grading, undo, daily limits
  Views/                profile picker, deck list, study, card editor,
                        rapid capture, import, statistics
UITests/          42 UI tests
```

## Known gaps

- No automated coverage of the view layer; the screens are checked by hand.
- No export, and no Anki `.apkg` import (CSV only).
- Handwriting is self-graded — no recognition, by design.
- Undo is one step deep.
