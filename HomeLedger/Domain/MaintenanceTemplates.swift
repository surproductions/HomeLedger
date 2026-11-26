import Foundation

/// Editable suggestions — not prescriptions. The UI states that intervals vary by home,
/// equipment and climate, and that manufacturer guidance takes precedence.
struct MaintenanceTemplate: Identifiable, Hashable {
    let key: String
    let title: String
    let details: String
    let recurrence: Recurrence
    let symbol: String
    let season: String?
    var id: String { key }

    static let all: [MaintenanceTemplate] = [
        .init(key: "hvac-filter", title: "Replace HVAC filter", details: "Check the filter size printed on the frame. Many filters are changed every 1–3 months; homes with pets or allergies may need more frequent changes.", recurrence: .every(3, .month, basis: .completion), symbol: "fan", season: nil),
        .init(key: "smoke-test", title: "Test smoke & CO detectors", details: "Press the test button on each detector. Replace batteries as needed.", recurrence: .every(1, .month), symbol: "smoke", season: nil),
        .init(key: "dishwasher-filter", title: "Clean dishwasher filter", details: "Remove and rinse the filter at the bottom of the tub.", recurrence: .every(1, .month, basis: .completion), symbol: "dishwasher", season: nil),
        .init(key: "fridge-water-filter", title: "Replace refrigerator water filter", details: "Use the filter model listed in your refrigerator manual.", recurrence: .every(6, .month, basis: .completion), symbol: "drop.triangle", season: nil),
        .init(key: "gutters", title: "Clean gutters", details: "Clear leaves and debris; check downspouts drain away from the foundation.", recurrence: .every(1, .year), symbol: "house", season: "Autumn"),
        .init(key: "water-heater", title: "Flush water heater", details: "Draining sediment can help efficiency. Follow your water heater's manual.", recurrence: .every(1, .year), symbol: "flame", season: nil),
        .init(key: "dryer-vent", title: "Clean dryer vent", details: "Clean the lint trap housing and exterior vent duct.", recurrence: .every(1, .year), symbol: "wind", season: nil),
        .init(key: "range-hood", title: "Clean range hood filter", details: "Degrease or replace the hood filter.", recurrence: .every(3, .month, basis: .completion), symbol: "stove", season: nil),
        .init(key: "hvac-service", title: "Seasonal HVAC check-up", details: "Schedule a professional inspection before heavy heating or cooling season.", recurrence: .every(1, .year), symbol: "thermometer.medium", season: "Spring / Autumn"),
        .init(key: "spring-check", title: "Spring exterior walk-around", details: "Look for roof, siding, window seal and drainage issues after winter.", recurrence: .every(1, .year), symbol: "leaf", season: "Spring"),
        .init(key: "winterize", title: "Winterize outdoor faucets", details: "Shut off and drain exterior hose bibs before freezing weather.", recurrence: .every(1, .year), symbol: "snowflake", season: "Autumn"),
        .init(key: "gfci-test", title: "Test GFCI outlets", details: "Press TEST then RESET on kitchen, bathroom and outdoor outlets.", recurrence: .every(6, .month), symbol: "poweroutlet.type.b", season: nil)
    ]

    static func template(forKey key: String) -> MaintenanceTemplate? { all.first { $0.key == key } }
}

/// Suggested rooms offered during onboarding — all optional.
enum RoomSuggestions {
    static let all: [(name: String, symbol: String)] = [
        ("Kitchen", "refrigerator"), ("Living Room", "sofa"), ("Primary Bedroom", "bed.double"),
        ("Bathroom", "shower"), ("Laundry", "washer"), ("Garage", "car"), ("Office", "desktopcomputer"),
        ("Dining Room", "fork.knife"), ("Basement", "stairs"), ("Utility Room", "wrench.and.screwdriver"),
        ("Outdoor", "tree"), ("Kids' Room", "teddybear")
    ]
    static let defaults: Set<String> = ["Kitchen", "Living Room", "Primary Bedroom", "Laundry", "Garage"]

    static let symbolChoices = ["refrigerator", "sofa", "bed.double", "shower", "washer", "car", "desktopcomputer", "fork.knife", "stairs",
                                "wrench.and.screwdriver", "tree", "teddybear", "tv", "books.vertical", "dumbbell", "door.left.hand.open",
                                "lamp.desk", "toilet", "sun.max", "square.split.bottomrightquarter"]
}
