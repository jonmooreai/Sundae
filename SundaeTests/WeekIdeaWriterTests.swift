import Foundation
import Testing
@testable import Sundae

/// Ideas the phone's own model writes for the week. The model is not on the test machine, so
/// these check everything around it: the checks every idea must pass, what the model is told,
/// and how the week's ideas take their days in the app, the widget and Siri.
struct WeekIdeaWriterTests {
    let catalog = SuggestionCatalog.bundled()
    let zone = TimeZone(identifier: "America/Indiana/Indianapolis")!

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    /// November 2, 2026 is a Monday.
    private func date(_ day: Int, month: Int = 11, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private func accepts(_ text: String, _ reason: String) -> Bool {
        WeekIdeaWriter.accepts(text: text, reason: reason, avoiding: catalog.all.map(\.text))
    }

    @Test func aWarmNewIdeaIsKept() {
        #expect(accepts("Gather a handful of fallen leaves in every color.",
                        "Autumn only lays them out like this for a little while."))
        #expect(accepts("Plant a few bulbs for the spring.", "Future you will be so glad you did."))
        #expect(accepts("Bake a loaf of bread and share half.",
                        "Warm bread tastes better when someone else gets the heel."))
    }

    /// It knows nothing real about anywhere, so it names nothing: no place, person, day or month.
    @Test func itNamesNothing() {
        #expect(!accepts("Visit Riverside Park and feed the ducks.", "They will be glad to see you."))
        #expect(!accepts("Bake something for Pat Doe.", "A small surprise goes a long way."))
        #expect(!accepts("Bake something slow on Saturday.", "A quiet day calls for it."))
        #expect(!accepts("Make a little wreath for the door.", "It will make November feel cozy."))
        #expect(WeekIdeaWriter.namesNothing("Write down three things I'm glad about."))
    }

    /// The app asks for the photo itself.
    @Test func itNeverAsksForAPicture() {
        #expect(!accepts("Take a photo of the leaves turning.", "Autumn is so pretty this time of year."))
        #expect(!accepts("Find a tree that looks like a picture.", "Autumn is so pretty this time of year."))
    }

    @Test func nothingAfterDarkNoNumbersNoShouting() {
        #expect(!accepts("Watch the stars from your back step.", "The sky is clearer when it is cold."))
        #expect(!accepts("Bake cookies for three friends.", "Everyone loves a tin of cookies, 2 dozen."))
        #expect(!accepts("Bake cookies for a friend.", "Everyone loves a tin of cookies!"))
        #expect(!accepts("Write a letter to someone you miss \u{2014} by hand.", "It will mean more than a text."))
        #expect(!accepts("Cook a soup that takes all afternoon.", "The whole home smells like a hug."))
        // Lines that would fail a hand-written idea fail here too.
        #expect(!accepts("Share a beer with a friend on the porch.", "Slow talks are the best ones."))
    }

    @Test func itStartsWithSomethingToDo() {
        #expect(!accepts("You should call your grandmother.", "She would love to hear from you."))
        #expect(!accepts("The leaves are turning everywhere.", "Go and find the reddest one you can."))
    }

    /// Something new each time, not the catalog in other words.
    @Test func itIsNotACopy() {
        #expect(!accepts("Walk a neighborhood you don't know.", "Pick a direction and take the first street."))
        #expect(WeekIdeaWriter.isRepeat("Watch the sunset from a hill.", of: ["Watch the sunset from somewhere high."]))
        #expect(!WeekIdeaWriter.isRepeat("Plant a few bulbs for the spring.", of: ["Watch the sunset from somewhere high."]))
    }

    /// The model copies its examples, so every example passes the checks itself.
    @Test func everyExampleWouldPass() {
        for angle in WeekIdeaWriter.angles {
            let examples = WeekIdeaWriter.examples(for: angle, from: catalog)
            #expect(examples.count == 6, "\(angle.words)")
            #expect(Set(examples.map(\.id)).count == examples.count)
            for example in examples {
                #expect(WeekIdeaWriter.accepts(text: example.text, reason: example.reason, avoiding: []), "\(example.text)")
            }
        }
    }

    @Test func theModelIsToldTheSeasonTheAngleAndNothingAboutYou() {
        let angle = WeekIdeaWriter.angles[0]
        let prompt = WeekIdeaWriter.prompt(season: "late autumn, November", angle: angle,
                                           thisWeek: ["Plant a few bulbs for the spring."])
        #expect(prompt.contains("late autumn, November"))
        #expect(prompt.contains(angle.words))
        #expect(prompt.contains("Plant a few bulbs for the spring."))
        let instructions = WeekIdeaWriter.instructions(examples: WeekIdeaWriter.examples(for: angle, from: catalog))
        for text in [prompt, instructions] {
            #expect(!text.contains("\u{2014}"), "no em-dashes")
            #expect(!text.contains("\u{2013}"))
        }
        // Every angle is something the guard would let through.
        for angle in WeekIdeaWriter.angles {
            #expect(IdeaGuard.isSafeText(angle.words), "\(angle.words)")
        }
    }

    @Test func theSeasonIsTheOneWhereThePhoneIs() {
        #expect(WeekIdeaWriter.season(for: date(2), calendar: calendar) == "late autumn, November")
        #expect(WeekIdeaWriter.season(for: date(15, month: 1), calendar: calendar) == "the middle of winter, January")
        #expect(WeekIdeaWriter.season(for: date(1, month: 3), calendar: calendar) == "early spring, March")
        var sydney = Calendar(identifier: .gregorian)
        sydney.timeZone = TimeZone(identifier: "Australia/Sydney")!
        #expect(WeekIdeaWriter.season(for: date(2), calendar: sydney) == "late spring, November")
        #expect(WeekIdeaWriter.isSouthern(TimeZone(identifier: "America/Argentina/Buenos_Aires")!))
        #expect(!WeekIdeaWriter.isSouthern(TimeZone(identifier: "Europe/London")!))
    }

    /// Each day of a week gets its own angle, and a second try never borrows another day's.
    @Test func everyDayHasItsOwnAngle() {
        let week = (2...7).map { date($0) }
        let first = week.map { WeekIdeaWriter.angle(for: $0, calendar: calendar).words }
        let second = week.map { WeekIdeaWriter.angle(for: $0, calendar: calendar, attempt: 1).words }
        #expect(Set(first).count == 6)
        #expect(Set(second).isDisjoint(with: first))
        let nextMonday = WeekIdeaWriter.angle(for: date(9), calendar: calendar).words
        #expect(nextMonday != first[0], "a new week starts somewhere new")
    }

    @Test func theWeekIsWrittenFromTodayToSaturday() {
        func days(_ day: Int) -> Int {
            let now = date(day)
            return WrittenIdeasStore.daysLeft(clock: SundayClock(now: { now }, timeZone: zone)).count
        }
        #expect(days(2) == 6, "Monday")
        #expect(days(5) == 3, "Thursday")
        #expect(days(7) == 1, "Saturday")
        #expect(days(8) == 0, "Sunday")
    }

    /// A written idea names its day and nothing else, so it is safe to send with the account.
    @Test func aWrittenIdeaTakesItsDay() {
        let tuesday = Suggestion(id: Suggestion.writtenID(for: date(3), calendar: calendar),
                                 text: "Plant a few bulbs for the spring.", reason: "Future you will be so glad you did.",
                                 categories: [.outdoors], timeOfDay: .any)
        #expect(tuesday.id == "written:2026-11-03")
        #expect(tuesday.isWritten && !tuesday.isNearby)
        #expect(catalog.suggestion(forDay: date(3), calendar: calendar, written: [tuesday]) == tuesday)
        // Other days, or once it is done, the catalog's pick as before.
        #expect(catalog.suggestion(forDay: date(4), calendar: calendar, written: [tuesday])
            == catalog.suggestion(forDay: date(4), calendar: calendar))
        #expect(catalog.suggestion(forDay: date(3), calendar: calendar, written: [tuesday], done: [tuesday.id])
            == catalog.suggestion(forDay: date(3), calendar: calendar))
    }

    /// The widget's next two days show the ideas written for them.
    @Test func theWidgetLooksAheadToWrittenIdeas() {
        let wednesday = Suggestion(id: Suggestion.writtenID(for: date(4), calendar: calendar),
                                   text: "Plant a few bulbs for the spring.", reason: "Future you will be so glad you did.",
                                   categories: [.outdoors], timeOfDay: .any)
        let tuesday = date(3)
        let clock = SundayClock(now: { tuesday }, timeZone: zone)
        let upcoming = WidgetSnapshotBuilder.upcoming(after: tuesday, clock: clock, catalog: catalog, written: [wednesday])
        #expect(upcoming.first?.text == wednesday.text)
        #expect(upcoming.count == 2)
    }
}
