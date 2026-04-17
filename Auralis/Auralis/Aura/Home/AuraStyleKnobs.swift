//
//  AuraStyleKnobs.swift
//  Auralis
//
//  Created by Daniel Bell on 10/20/25.
//

import Foundation

/// Public knobs for style and scenery
public enum AvatarStyle: String, CaseIterable {
    case abstract
    case character
    case geometric
}

/// Supported rendering lanes for Aura-generated scenery.
public enum AuroraLane: String { case poster, photoreal, synthwave }

/// Supported scenery presets for Aura background generation.
public enum AuroraScene: String, Identifiable, CaseIterable {
    /// Stable identifier for use in SwiftUI selection APIs.
    public var id: String {
        rawValue
    }

    // Natural landscapes
    case prairie
    case mountain
    case lake
    case coastline
    case borealForest
    case tundra
    case fjord
    case glacier
    case iceberg
    case riverValley
    case waterfall
    case canyon
    case badlands
    case island
    case highlands
    // Human elements
    case citySkyline
    case ruralFarm
    case cabin
    case lighthouse
    case observatory
    case bridge
    // Arctic/expedition flavor
    case iceRoad
    case polarCamp
    case researchStation
}

extension AuroraScene {
    var label: String {
        switch self {
        case .prairie: return "Prairie"
        case .mountain: return "Mountain"
        case .lake: return "Lake"
        case .coastline: return "Coastline"
        case .borealForest: return "Boreal Forest"
        case .tundra: return "Tundra"
        case .fjord: return "Fjord"
        case .glacier: return "Glacier"
        case .iceberg: return "Iceberg"
        case .riverValley: return "River Valley"
        case .waterfall: return "Waterfall"
        case .canyon: return "Canyon"
        case .badlands: return "Badlands"
        case .island: return "Island"
        case .highlands: return "Highlands"
        case .citySkyline: return "City Skyline"
        case .ruralFarm: return "Rural Farm"
        case .cabin: return "Cabin"
        case .lighthouse: return "Lighthouse"
        case .observatory: return "Observatory"
        case .bridge: return "Bridge"
        case .iceRoad: return "Ice Road"
        case .polarCamp: return "Polar Camp"
        case .researchStation: return "Research Station"
        }
    }
}
