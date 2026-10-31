import Foundation
import Testing
@testable import ScooterCore

struct SavedPlacesTests {
    @Test func persistenceAndNamedPlaces() throws {
        var places = SavedPlaces()
        try places.merge([
            SavedPlace(name: "Home", latitude: 40, longitude: -74),
            SavedPlace(name: "Work", latitude: 40.1, longitude: -74.1),
            SavedPlace(name: "Coffee", latitude: 40.2, longitude: -74.2)
        ])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("places.json")
        try places.save(to: url)
        #expect(try SavedPlaces.load(from: url) == places)
        #expect(places.visible.map(\.name) == ["Coffee", "Home", "Work"])
    }

    @Test func deletionCannotBeResurrectedByOldSnapshot() throws {
        let date = Date(timeIntervalSince1970: 100)
        let old = SavedPlace(name: "Home", latitude: 40, longitude: -74, modifiedAt: date)
        var phone = SavedPlaces()
        var watch = SavedPlaces()
        try phone.merge([old])
        try watch.merge(phone.records)
        try phone.delete(id: old.id, at: date.addingTimeInterval(10))
        try phone.merge(watch.records)
        try watch.merge(phone.records)
        #expect(phone.visible.isEmpty)
        #expect(watch.visible.isEmpty)
        #expect(phone == watch)
        #expect(phone.records.count == 1)
    }

    @Test func concurrentEditsConvergeAndDeletionWinsTies() throws {
        let original = SavedPlace(name: "Home", latitude: 40, longitude: -74)
        var renamed = original
        renamed.name = "Apartment"
        var deleted = original
        deleted.deleted = true
        var first = SavedPlaces()
        var second = SavedPlaces()
        try first.merge([original, renamed, deleted])
        try second.merge([deleted, renamed, original])
        #expect(first == second)
        #expect(first.visible.isEmpty)
    }

    @Test func invalidPlacesDoNotMutateState() throws {
        var places = SavedPlaces()
        let invalid = SavedPlace(name: "", latitude: .nan, longitude: 500)
        #expect(throws: (any Error).self) { try places.merge([invalid]) }
        #expect(places.records.isEmpty)
    }
}
