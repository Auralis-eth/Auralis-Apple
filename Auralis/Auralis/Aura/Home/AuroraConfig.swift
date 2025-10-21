//
//  AuroraConfig 2.swift
//  Auralis
//
//  Created by Daniel Bell on 10/20/25.
//


struct AuroraConfig {
    static let compositions = [
        "rayed arcs",
        "curtain",
        "banded horizon",
        "corona overhead",
        "diffuse veil",
        "multi-band ripples"
    ]
    static let moods = [
        "calm",
        "mystical",
        "dramatic",
        "serene",
        "electric"
    ]

    /// Tasteful chain motifs (no logos, no on-canvas text)
    static let chainThemes: [String:String] = [
        "1"    : "diamond-facet shimmer, prismatic refractions",
        "mainnet":"diamond-facet shimmer, prismatic refractions",
        "ethereum":"diamond-facet shimmer, prismatic refractions",
        "10"   : "silky fast filaments, forward motion hints",
        "8453" : "clean minimal gradients, architectural calm",
        "42161": "layered ribbons, braided strands",
        "137"  : "soft geometric tessellations in light"
    ]
}
