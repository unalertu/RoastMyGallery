import Foundation

/// Turns raw on-device Vision classification labels into a small, friendly,
/// user-likable topic vocabulary — applied once, in `StatsAggregator`, before
/// anything is counted, indexed, or sent to the insight backend.
///
/// WHY THIS EXISTS: `VNClassifyImageRequest` emits hundreds of hierarchical
/// labels, many of them generic filler ("indoor", "structure", "material") or
/// near-duplicates ("cuisine" / "meal" / "plate" all meaning food). Fed
/// straight into the narrative they made insights read like a computer-vision
/// dump and always fixate on the same bland labels. This maps the useful ones
/// onto friendly topic names, merges synonyms so their counts combine, and
/// drops the filler — giving the LLM richer, nicer subjects to talk about.
///
/// CONSISTENCY: the friendly name a label maps to becomes the key used in BOTH
/// `PhotoStats.topCategories` (sent to the backend, tagged onto segments) and
/// `AnalysisRecord.categoryPhotoIndex` (the on-device photo lookup). Mapping in
/// exactly one place keeps those two keyspaces identical, so a segment tagged
/// "food" always resolves to a photo indexed under "food".
///
/// PRIVACY: pure string transforms — no image data, no asset IDs. The
/// aggregate-only privacy contract is unchanged.
enum CategoryVocabulary {
    /// Raw Vision labels we never surface — too generic to be interesting, or
    /// structural noise. Matched against the normalized form of the label.
    private static let blocklist: Set<String> = [
        "indoor", "outdoor", "structure", "material", "material_property",
        "surface", "background", "object", "scene", "abstract", "still_life",
        "macro", "close_up", "monochrome", "pattern", "texture", "light",
        "reflection", "shadow", "room", "interior", "wall", "floor", "ceiling",
        "furniture", "person", "people", "human", "face", "body_part",
        "portrait", "selfie", // selfie is tracked as its own synthetic tag
    ]

    /// Raw Vision label → friendly topic. Many labels collapse onto one topic
    /// so their counts merge. Keys are normalized (lowercased; spaces and
    /// hyphens → underscores). Anything not listed falls through to a
    /// prettified version of the raw label (see `friendlyName`), so the long
    /// tail stays usable without hand-listing every label.
    private static let map: [String: String] = [
        // Food & drink
        "food": "food", "cuisine": "food", "meal": "food", "dish": "food",
        "plate": "food", "fruit": "food", "vegetable": "food",
        "dessert": "sweets", "cake": "sweets", "pastry": "sweets",
        "drink": "drinks", "beverage": "drinks", "cocktail": "drinks",
        "wine": "drinks", "beer": "drinks", "coffee": "coffee",
        // Nature & outdoors
        "nature": "nature", "landscape": "scenery", "scenery": "scenery",
        "mountain": "mountains", "hill": "mountains", "sky": "skies",
        "cloud": "skies", "sunset": "golden hour", "sunrise": "golden hour",
        "beach": "the beach", "sea": "the ocean", "ocean": "the ocean",
        "water": "water", "lake": "water", "river": "water",
        "forest": "nature", "tree": "plants", "plant": "plants",
        "garden": "plants", "flower": "flowers", "flower_arrangement": "flowers",
        "snow": "snow",
        // City & travel
        "building": "architecture", "architecture": "architecture",
        "city": "city life", "street": "city life", "skyline": "city life",
        "bridge": "architecture", "monument": "landmarks",
        "landmark": "landmarks", "travel": "travel",
        // Nightlife & events
        "concert": "concerts", "stage": "concerts", "performance": "concerts",
        "crowd": "events", "party": "nights out", "nightlife": "nights out",
        "festival": "events", "fireworks": "events",
        // Vehicles
        "car": "cars", "vehicle": "cars", "motorcycle": "cars",
        "bicycle": "bikes", "boat": "boats", "airplane": "travel",
        "train": "travel",
        // Animals (Vision classification — distinct from VNRecognizeAnimals)
        "cat": "cats", "dog": "dogs", "bird": "birds", "horse": "horses",
        "fish": "fish", "animal": "animals",
        // People & moments
        "wedding": "weddings", "baby": "family", "child": "family",
        "sport": "sports", "sports": "sports", "gym": "the gym",
        "fitness": "the gym", "yoga": "the gym", "dance": "dancing",
        // Screens & objects
        "document": "documents", "text": "screens full of text",
        "receipt": "receipts", "art": "art", "painting": "art",
        "drawing": "art", "fashion": "fashion", "clothing": "fashion",
        "shoe": "fashion", "book": "books",
        // Music
        "instrument": "music", "musical_instrument": "music",
        "guitar": "music", "piano": "music", "headphones": "music",
        "vinyl": "music", "record_player": "music",
        // The outdoors (activity — distinct from the "nature" scenery topic)
        "hiking": "the outdoors", "camping": "the outdoors",
        "tent": "the outdoors", "trail": "the outdoors",
        "backpack": "the outdoors", "campfire": "the outdoors",
        // Cooking (the act — plated results still map to "food")
        "kitchen": "cooking", "cooking": "cooking", "baking": "cooking",
        "ingredient": "cooking", "cookware": "cooking",
        // Shopping
        "shop": "shopping", "market": "shopping", "store": "shopping",
        "mall": "shopping", "bazaar": "shopping", "supermarket": "shopping",
        // Work life
        "office": "work life", "desk": "work life", "laptop": "work life",
        "meeting": "work life", "whiteboard": "work life",
        // Gadgets
        "phone": "gadgets", "smartphone": "gadgets", "electronics": "gadgets",
        "keyboard": "gadgets", "camera": "gadgets", "headset": "gadgets",
        // Night skies
        "moon": "night skies", "stars": "night skies",
        "night_sky": "night skies", "astronomy": "night skies",
        "milky_way": "night skies",
        // The pool
        "pool": "the pool", "swimming": "the pool", "swimmer": "the pool",
        "swimming_pool": "the pool",
        // Parks
        "park": "parks", "picnic": "parks", "playground": "parks",
        "lawn": "parks", "bench": "parks",
        // Museums
        "museum": "museums", "exhibition": "museums",
        "sculpture": "museums", "gallery": "museums", "statue": "museums",
        // Toys
        "toy": "toys", "lego": "toys", "doll": "toys",
        "board_game": "toys", "puzzle": "toys",
        // Weather moods
        "rain": "weather moods", "storm": "weather moods",
        "fog": "weather moods", "rainbow": "weather moods",
        "lightning": "weather moods", "mist": "weather moods",
        // Gaming
        "video_game": "gaming", "arcade": "gaming", "console": "gaming",
        "gamepad": "gaming",
    ]

    /// Normalize a raw label for lookup: lowercase, trim, collapse separators.
    private static func normalize(_ raw: String) -> String {
        raw.lowercased()
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    /// Map one raw Vision label to a friendly topic, or `nil` to drop it.
    static func topic(for rawLabel: String) -> String? {
        let key = normalize(rawLabel)
        guard !key.isEmpty, !blocklist.contains(key) else { return nil }
        if let mapped = map[key] { return mapped }
        return friendlyName(from: key)
    }

    /// Fallback prettifier for labels we haven't explicitly curated: turn
    /// "still_water" into "still water". Structural noise is already filtered
    /// by the blocklist; here we only guard against single-letter / numeric junk.
    private static func friendlyName(from normalizedKey: String) -> String? {
        let pretty = normalizedKey.replacingOccurrences(of: "_", with: " ")
        guard pretty.count >= 3, pretty.contains(where: { $0.isLetter }) else { return nil }
        return pretty
    }

    /// Map a photo's raw labels to friendly topics, dropping blocked ones and
    /// de-duplicating within the photo (so "food" + "plate" count once, not
    /// twice) while preserving Vision's confidence order.
    static func topics(for rawLabels: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for label in rawLabels {
            guard let topic = topic(for: label), !seen.contains(topic) else { continue }
            seen.insert(topic)
            result.append(topic)
        }
        return result
    }

    /// Like `topics(for:)` but preserves each topic's Vision confidence, so
    /// callers can rank a category's representative photos by match strength.
    /// When several raw labels collapse to one topic, the first one wins —
    /// and since Vision returns results confidence-descending, that's the
    /// highest-confidence label — matching `topics(for:)`'s de-duplication.
    static func scoredTopics(
        for scoredLabels: [PhotoObservation.ScoredCategory]
    ) -> [(topic: String, confidence: Float)] {
        var seen: Set<String> = []
        var result: [(topic: String, confidence: Float)] = []
        for label in scoredLabels {
            guard let topic = topic(for: label.identifier), !seen.contains(topic) else { continue }
            seen.insert(topic)
            result.append((topic, label.confidence))
        }
        return result
    }
}
