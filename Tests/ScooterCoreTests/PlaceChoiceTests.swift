import Foundation
import Testing
@testable import ScooterCore

struct PlaceChoiceTests {
    @Test func rejectsResultsThatCannotBeRoutedOrSaved() {
        #expect(PlaceChoice(name: "Park", latitude: .nan, longitude: 0) == nil)
        #expect(PlaceChoice(name: "Park", latitude: 40, longitude: .infinity) == nil)
        #expect(PlaceChoice(name: "Park", latitude: 91, longitude: 0) == nil)
        #expect(PlaceChoice(name: "Park", latitude: 0, longitude: -181) == nil)
        // MapKit's invalid-coordinate sentinel.
        #expect(PlaceChoice(name: "Park", latitude: -180, longitude: -180) == nil)
        #expect(PlaceChoice(name: "  \n", address: " ", latitude: 40, longitude: -74) == nil)
        #expect(PlaceChoice(name: nil, address: nil, latitude: 40, longitude: -74) == nil)
    }

    @Test func labelFallsBackToTheAddressAndIsTrimmed() throws {
        let named = try #require(PlaceChoice(name: "  Central Park \n", address: "New York, NY", latitude: 40.78, longitude: -73.96))
        #expect(named.name == "Central Park")
        let unnamed = try #require(PlaceChoice(name: nil, address: "1 Main St, Springfield", latitude: 40, longitude: -74))
        #expect(unnamed.name == "1 Main St, Springfield")
        #expect(unnamed.detail.isEmpty)
    }

    @Test func detailDropsOnlyAWholeLeadingName() throws {
        let street = try #require(PlaceChoice(name: "1 Main St", address: "1 Main St, Springfield, IL 62701", latitude: 40, longitude: -74))
        #expect(street.detail == "Springfield, IL 62701")
        let caseInsensitive = try #require(PlaceChoice(name: "1 MAIN ST", address: "1 Main St\nSpringfield", latitude: 40, longitude: -74))
        #expect(caseInsensitive.detail == "Springfield")
        let partialWord = try #require(PlaceChoice(name: "Park", address: "Parkview Avenue, Springfield", latitude: 40, longitude: -74))
        #expect(partialWord.detail == "Parkview Avenue, Springfield")
        let unrelated = try #require(PlaceChoice(name: "Joe's Coffee", address: "9 Elm St, Springfield", latitude: 40, longitude: -74))
        #expect(unrelated.detail == "9 Elm St, Springfield")
        let identical = try #require(PlaceChoice(name: "Springfield", address: "springfield", latitude: 40, longitude: -74))
        #expect(identical.detail.isEmpty)
    }

    @Test func suggestedSavedNameAlwaysFitsTheSavedPlaceLimit() throws {
        let long = String(repeating: "A", count: 250)
        let choice = try #require(PlaceChoice(name: long, latitude: 40, longitude: -74))
        #expect(choice.suggestedSavedName.count == PlaceChoice.maxSavedNameLength)
        #expect(SavedPlace(name: choice.suggestedSavedName, latitude: choice.latitude, longitude: choice.longitude).isValid)
    }

    @Test func savedPlacesBecomeChoicesAndInvalidOnesDoNot() throws {
        let home = SavedPlace(name: "Home", latitude: 40, longitude: -74)
        let choice = try #require(PlaceChoice(home))
        #expect(choice.name == "Home")
        #expect(choice.latitude == 40 && choice.longitude == -74)
        #expect(PlaceChoice(SavedPlace(name: "Nowhere", latitude: 400, longitude: 0)) == nil)
    }

    @Test func distanceIsMetersAndSymmetricWithRideMath() throws {
        let choice = try #require(PlaceChoice(name: "Central Park", latitude: 40.7829, longitude: -73.9654))
        #expect(choice.distance(fromLatitude: 40.7829, longitude: -73.9654) == 0)
        // One degree of latitude is about 111.2 km.
        let degree = choice.distance(fromLatitude: 39.7829, longitude: -73.9654)
        #expect(abs(degree - 111_195) < 200)
    }

    @Test func identityDistinguishesSameNamedPlaces() throws {
        let first = try #require(PlaceChoice(name: "Starbucks", latitude: 40.1, longitude: -74.1))
        let second = try #require(PlaceChoice(name: "Starbucks", latitude: 40.2, longitude: -74.2))
        #expect(first.id != second.id)
        #expect(Set([first, second, first]).count == 2)
    }
}

struct MatchHighlightingTests {
    private func emphasized(_ text: AttributedString) -> [String] {
        text.runs.filter { $0.inlinePresentationIntent == .stronglyEmphasized }.map { String(text[$0.range].characters) }
    }

    @Test func emphasizesOnlyTheTypedRanges() {
        let text = MatchHighlighting.attributed("Central Park", ranges: [NSRange(location: 0, length: 3), NSRange(location: 8, length: 4)])
        #expect(String(text.characters) == "Central Park")
        #expect(emphasized(text) == ["Cen", "Park"])
    }

    @Test func ignoresRangesThatDoNotFitTheText() {
        let text = MatchHighlighting.attributed("Park", ranges: [
            NSRange(location: 2, length: 50), NSRange(location: 40, length: 2),
            NSRange(location: NSNotFound, length: 0), NSRange(location: 1, length: 0)
        ])
        #expect(String(text.characters) == "Park")
        #expect(emphasized(text).isEmpty)
    }

    @Test func rangesAreUTF16OffsetsSoEmojiDoNotShiftTheMatch() {
        let title = "Café ☕️ 👩🏽‍💻 Lounge"
        let range = (title as NSString).range(of: "Lounge")
        let text = MatchHighlighting.attributed(title, ranges: [range])
        #expect(emphasized(text) == ["Lounge"])
    }

    @Test func overlappingRangesAreHarmless() {
        let text = MatchHighlighting.attributed("Central Park", ranges: [NSRange(location: 0, length: 5), NSRange(location: 3, length: 4)])
        #expect(emphasized(text) == ["Central"])
    }
}
