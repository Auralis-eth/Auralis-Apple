//
//  DisplayModel.swift
//  Auralis
//
//  Created by Daniel Bell on 3/22/25.
//


import Foundation

struct NFTAnimation: Identifiable {
    enum SourceType {
        case ipfs
        case website
        case url
        case artBlocks
    }
    var id = UUID()
    
    let details: [String: Any]?
    let animations: [URL]?
    let source: SourceType
}

