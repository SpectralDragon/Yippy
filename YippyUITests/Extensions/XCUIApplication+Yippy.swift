//
//  XCUIApplication+Yippy.swift
//  YippyUITests
//
//  Created by Matthew Davidson on 30/9/19.
//  Copyright © 2019 MatthewDavidson. All rights reserved.
//

import XCTest

extension XCUIApplication {
    
    var yippyTableView: XCUIElement {
        return yippyWindow.descendants(matching: .any).matching(identifier: Accessibility.identifiers.yippyTableView).firstMatch
    }
    
    var yippyTableViewItems: XCUIElementQuery {
        let notificationItems = yippyTableView.descendants(matching: .any).matching(identifier: Accessibility.identifiers.yippyNotificationCell)
        if notificationItems.count > 0 {
            return notificationItems
        }
        return yippyTableView.cells
    }
    
    func getYippyTableViewCell(at i: Int) -> XCUIElement {
        return yippyTableViewItems.element(boundBy: i)
    }
    
    func getYippyTableViewCellTextView(at i: Int) -> XCUIElement {
        let cell = getYippyTableViewCell(at: i)
        let notificationText = cell.descendants(matching: .any).matching(identifier: Accessibility.identifiers.yippyNotificationPrimaryText).firstMatch
        if notificationText.exists {
            return notificationText
        }
        return cell.children(matching: .textView).matching(identifier: Accessibility.identifiers.yippyItemTextView).element
    }
    
    func getYippyTableViewItemString(at i: Int) -> String? {
        let element = getYippyTableViewCellTextView(at: i)
        return element.value as? String ?? element.label
    }
    
    func getYippyTableViewCellType(at i: Int) -> String {
        return getYippyTableViewCell(at: i).label
    }
}
