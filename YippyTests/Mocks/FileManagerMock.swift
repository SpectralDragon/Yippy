//
//  FileManagerMock.swift
//  YippyTests
//
//  Created by Matthew Davidson on 20/10/19.
//  Copyright © 2019 MatthewDavidson. All rights reserved.
//

import XCTest
@testable import Yippy

class FileManagerMock: FileManager {
    
    var directoryContents = [URL: [URL]?]()
    var itemAttributes = [String: [FileAttributeKey: Any]]()
    
    var createDirectory = [URL: Bool]()
    
    var removeItem = [URL: Bool]()

    override func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
        let url = URL(fileURLWithPath: path)
        if let contents = directoryContents[url] {
            isDirectory?.pointee = ObjCBool(contents != nil)
            return true
        }
        return false
    }
    
    override func contentsOfDirectory(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?, options mask: FileManager.DirectoryEnumerationOptions = []) throws -> [URL] {
        if let contents = directoryContents[url] as? [URL] {
            return contents
        }
        else {
            throw NSError(domain: "FileManagerTests", code: 0)
        }
    }
    
    override func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey : Any]? = nil) throws {
        if createDirectory[url] == nil || createDirectory[url] == false {
            throw NSError(domain: "FileManagerTests", code: 0)
        }
    }
    
    override func removeItem(at URL: URL) throws {
        if removeItem[URL] == nil || removeItem[URL] == false {
            throw NSError(domain: "FileManagerTests", code: 0)
        }
    }

    override func attributesOfItem(atPath path: String) throws -> [FileAttributeKey : Any] {
        if let attributes = itemAttributes[path] {
            return attributes
        }
        throw NSError(domain: "FileManagerTests", code: 0)
    }
}
