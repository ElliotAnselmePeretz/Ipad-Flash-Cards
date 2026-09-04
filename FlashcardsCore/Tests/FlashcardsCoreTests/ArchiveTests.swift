import XCTest
@testable import FlashcardsCore

final class ArchiveTests: XCTestCase {

    let coder = ArchiveCoder()

    // Stand-in for real PencilKit ink: the point is that arbitrary bytes survive intact.
    private func ink(_ seed: UInt8, count: Int = 512) -> Data {
        Data((0..<count).map { UInt8(($0 &+ Int(seed)) % 256) })
    }

    private func sampleArchive() -> DeckArchive {
        var scheduling = SchedulingState.new()
        scheduling.phase = .review
        scheduling.intervalDays = 12.5
        scheduling.repetitions = 4
        scheduling.lapses = 2
        scheduling.memory = MemoryState(stability: 12.5, difficulty: 6.25)
        scheduling.lastReviewedAt = Date(timeIntervalSince1970: 1_700_000_000)
        scheduling.isLeech = true
        scheduling.isSuspended = true

        let review = ArchivedReview(
            id: UUID(), reviewedAt: Date(timeIntervalSince1970: 1_700_000_000),
            grade: .hard, intervalBefore: 8, intervalAfter: 12.5,
            easeAfter: 2.35, durationSeconds: 7.25
        )

        let card = ArchivedCard(
            id: UUID(), frontText: "the derivative of sin x", backText: "",
            frontDrawing: ink(1), backDrawing: ink(2, count: 2048),
            scheduling: scheduling,
            createdAt: Date(timeIntervalSince1970: 1_600_000_000),
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            reviews: [review]
        )

        let deck = ArchivedDeck(
            id: UUID(), name: "Derivatives", newCardsPerDay: 15, maximumReviewsPerDay: 150,
            createdAt: Date(timeIntervalSince1970: 1_600_000_000), cards: [card]
        )

        return DeckArchive(decks: [deck], exportedAt: Date(timeIntervalSince1970: 1_700_000_100))
    }

    // MARK: - Round trip

    func testArchiveSurvivesAnEncodeDecodeRoundTrip() throws {
        let original = sampleArchive().normalized()
        let restored = try coder.decode(coder.encode(original))
        XCTAssertEqual(restored, original, "a backup that does not restore exactly is not a backup")
    }

    func testNormalisingIsIdempotentSoRepeatedBackupsDoNotDrift() {
        let once = sampleArchive().normalized()
        XCTAssertEqual(once.normalized(), once)
    }

    func testTimestampsSurviveToMillisecondPrecision() throws {
        let precise = Date(timeIntervalSince1970: 1_700_000_000.123)
        var archive = sampleArchive().normalized()
        archive.decks[0].cards[0].scheduling.dueDate = precise
        let restored = try coder.decode(coder.encode(archive))
        XCTAssertEqual(restored.decks[0].cards[0].scheduling.dueDate.timeIntervalSince1970,
                       precise.timeIntervalSince1970, accuracy: 0.0005)
    }

    /// The whole reason this feature exists: handwriting cannot be retyped.
    func testHandwritingSurvivesExactly() throws {
        let original = sampleArchive()
        let restored = try coder.decode(coder.encode(original))
        let before = original.decks[0].cards[0]
        let after = restored.decks[0].cards[0]
        XCTAssertEqual(after.frontDrawing, before.frontDrawing)
        XCTAssertEqual(after.backDrawing, before.backDrawing)
        XCTAssertEqual(after.backDrawing?.count, 2048)
    }

    func testSchedulingStateSurvivesSoRestoredCardsResumeRatherThanRestart() throws {
        let restored = try coder.decode(coder.encode(sampleArchive()))
        let s = restored.decks[0].cards[0].scheduling
        XCTAssertEqual(s.phase, .review)
        XCTAssertEqual(s.intervalDays, 12.5)
        XCTAssertEqual(s.repetitions, 4)
        XCTAssertEqual(s.lapses, 2)
        XCTAssertEqual(s.memory?.stability, 12.5)
        XCTAssertEqual(s.memory?.difficulty, 6.25)
        XCTAssertTrue(s.isLeech)
        XCTAssertTrue(s.isSuspended)
        XCTAssertNotNil(s.lastReviewedAt)
    }

    func testReviewHistorySurvives() throws {
        let restored = try coder.decode(coder.encode(sampleArchive()))
        let review = restored.decks[0].cards[0].reviews.first
        XCTAssertEqual(review?.grade, .hard)
        XCTAssertEqual(review?.intervalBefore, 8)
        XCTAssertEqual(review?.durationSeconds, 7.25)
    }

    func testEmptyArchiveRoundTrips() throws {
        let empty = DeckArchive(decks: [])
        let restored = try coder.decode(coder.encode(empty))
        XCTAssertEqual(restored.decks.count, 0)
        XCTAssertEqual(restored.cardCount, 0)
    }

    func testCardWithNoInkRoundTrips() throws {
        let card = ArchivedCard(id: UUID(), frontText: "typed", backText: "answer",
                                frontDrawing: nil, backDrawing: nil,
                                scheduling: .new(), createdAt: Date(), modifiedAt: Date(),
                                reviews: [])
        let deck = ArchivedDeck(id: UUID(), name: "D", newCardsPerDay: 20,
                                maximumReviewsPerDay: 200, createdAt: Date(), cards: [card])
        let restored = try coder.decode(coder.encode(DeckArchive(decks: [deck])))
        XCTAssertNil(restored.decks[0].cards[0].frontDrawing)
        XCTAssertEqual(restored.decks[0].cards[0].backText, "answer")
    }

    // MARK: - Counts and naming

    func testCountsAreReported() {
        let archive = sampleArchive()
        XCTAssertEqual(archive.cardCount, 1)
        XCTAssertEqual(archive.reviewCount, 1)
    }

    func testSuggestedFilenameIsSortableAndTyped() {
        let name = coder.suggestedFilename(now: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertTrue(name.hasPrefix("InkRecall-"))
        XCTAssertTrue(name.hasSuffix(".inkrecall"))
    }

    // MARK: - Bad input

    func testGarbageIsRejectedWithAClearError() {
        let junk = Data("this is not a backup".utf8)
        XCTAssertThrowsError(try coder.decode(junk)) { error in
            XCTAssertEqual(error as? ArchiveCoder.ArchiveError, .notAnArchive)
        }
    }

    func testEmptyDataIsRejected() {
        XCTAssertThrowsError(try coder.decode(Data()))
    }

    func testArchiveFromANewerVersionIsRejectedRatherThanMisread() throws {
        var archive = sampleArchive()
        archive.formatVersion = DeckArchive.currentVersion + 5
        let data = try coder.encode(archive)
        XCTAssertThrowsError(try coder.decode(data)) { error in
            XCTAssertEqual(error as? ArchiveCoder.ArchiveError,
                           .unsupportedVersion(DeckArchive.currentVersion + 5))
        }
    }

    func testTruncatedFileIsRejected() throws {
        let data = try coder.encode(sampleArchive())
        let truncated = data.prefix(data.count / 2)
        XCTAssertThrowsError(try coder.decode(Data(truncated)))
    }

    // MARK: - Determinism

    func testTwoExportsOfUnchangedDataAreIdentical() throws {
        let archive = sampleArchive()
        XCTAssertEqual(try coder.encode(archive), try coder.encode(archive))
    }

    func testLargeArchiveRoundTripsIntact() throws {
        let cards = (0..<200).map { i in
            ArchivedCard(id: UUID(), frontText: "card \(i)", backText: "",
                         frontDrawing: ink(UInt8(i % 256), count: 4096), backDrawing: nil,
                         scheduling: .new(), createdAt: Date(), modifiedAt: Date(), reviews: [])
        }
        let deck = ArchivedDeck(id: UUID(), name: "Big", newCardsPerDay: 20,
                                maximumReviewsPerDay: 200, createdAt: Date(), cards: cards)
        let original = DeckArchive(decks: [deck]).normalized()
        let restored = try coder.decode(coder.encode(original))
        XCTAssertEqual(restored.cardCount, 200)
        XCTAssertEqual(restored.decks[0].cards[137].frontDrawing?.count, 4096)
        XCTAssertEqual(restored, original)
    }
}
