//
//  HistoryItem+YippyItem.swift
//  Yippy
//
//  Created by Matthew Davidson on 14/10/19.
//  Copyright © 2019 MatthewDavidson. All rights reserved.
//

import Foundation

extension HistoryItem {
    
    var content: HistoryItemContent {
        if types.contains(.fileURL) {
            return .thumbnailImage
        }
        else if types.contains(.URL) {
            return .webLink
        }
        else if types.contains(.color) {
            return .color
        }
        else if types.contains(.tiff) || types.contains(.png) {
            return .tiffOrPng
        }
        else {
            return .text
        }
    }
}

enum HistoryItemContent {
    case thumbnailImage
    case fileIcon
    case text
    case tiffOrPng
    case color
    case webLink
}
