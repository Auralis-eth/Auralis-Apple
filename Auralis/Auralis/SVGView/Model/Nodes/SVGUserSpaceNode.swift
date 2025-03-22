//
//  SVGUserSpaceNode.swift
//  Pods
//
//  Created by Alisa Mylnikova on 14/10/2020.
//

import SwiftUI

public class SVGUserSpaceNode: SVGNode {

    public enum UserSpace: String {

        case objectBoundingBox
        case userSpaceOnUse
    }

    public let node: SVGNode
    public let userSpace: UserSpace

    public init(node: SVGNode, userSpace: UserSpace) {
        self.node = node
        self.userSpace = userSpace
    }
    
    public func contentView() -> some View {
        SVGUserSpaceNodeView(model: self)
    }
}

struct SVGUserSpaceNodeView: View {
    let model: SVGUserSpaceNode

    var body: some View {
        if model.userSpace == .userSpaceOnUse {
            return model.node.toSwiftUI()
        } else {
            fatalError("Pass absolute node parameter for objectBoundingBox to work properly")
        }
    }
}
