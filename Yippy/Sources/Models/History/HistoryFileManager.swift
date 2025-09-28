//
//  HistoryFileManager.swift
//  Yippy
//
//  Created by Matthew Davidson on 20/10/19.
//  Copyright © 2019 MatthewDavidson. All rights reserved.
//

import Foundation
import Cocoa

/// Handles the interfacing with a `FileManager` object to save and retrieve history data.
class HistoryFileManager {
    
    var fileManager: FileManager
    var orderManager: ArrayFileManager
    var dataFileManager: DataFileManager
    var dispatchQueue: DispatchQueue
    var errorLogger: ErrorLogger
    var warningLogger: WarningLogger
    var alerter: Alerter
    
    static var `default` = HistoryFileManager()
    
    init(
        fileManager: FileManager = FileManager.default,
        orderManager: ArrayFileManager = ArrayFileManager(url: Constants.urls.historyOrder),
        dataFileManager: DataFileManager = DataFileManager(),
        dispatchQueue: DispatchQueue? = nil,
        errorLogger: ErrorLogger = .general,
        warningLogger: WarningLogger = .general,
        alerter: Alerter = .general
    ) {
        self.fileManager = fileManager
        self.orderManager = orderManager
        self.dataFileManager = dataFileManager
        self.errorLogger = errorLogger
        self.warningLogger = warningLogger
        self.alerter = alerter
        
        // Create a SERIAL background dispatch queue with a background quality of service. Can't just use DispatchQueue.global(qos: .background) as it's a concurrent queue, which we don't want
        // See: https://www.raywenderlich.com/5370-grand-central-dispatch-tutorial-for-swift-4-part-1-2
        self.dispatchQueue = dispatchQueue ?? DispatchQueue(label: "HistoryFileManagerQueue", qos: .background)
    }
    
    private func callHander(_ handler: ((Bool) -> Void)?, withVal val: Bool) {
        if let handler = handler {
            handler(val)
        }
    }
    
    private func writeHistoryOrder(history: [HistoryItem]) -> Bool {
        do {
            try checkHistoryDirectory()
            try self.orderManager.write(history.map({$0.fsId.uuidString}) as NSArray)
            return true
        }
        catch {
            let historyError = YippyError(localizedDescription: "Failed to write history order due to error: \(error.localizedDescription)")
            historyError.log(with: self.errorLogger)
            historyError.show(with: self.alerter)
            return false
        }
    }
    
    func checkHistoryDirectory() throws {
        var isDirectory: ObjCBool = false
        let url = Constants.urls.history
        
        // File doesn't exist
        if !fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        // File exists but it's not a directory
        else if !isDirectory.boolValue {
            try fileManager.removeItem(at: url)
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        // Directory is already set up.
    }
    
    func saveHistoryOrder(history: [HistoryItem], completionHandler: ((Bool) -> Void)? = nil) {
        dispatchQueue.async {
            let res = self.writeHistoryOrder(history: history)
            if let c = completionHandler {
                c(res)
            }
        }
    }
    
    func loadHistoryOrder() -> [UUID]? {
        guard let order = orderManager.read() as? [String] else {
            YippyWarning(localizedDescription: "Failed to load the history order.").log(with: warningLogger)
            return nil
        }
        var uuidOrder = [UUID]()
        for str in order {
            if let id = UUID(uuidString: str) {
                uuidOrder.append(id)
            }
            else {
                YippyWarning(localizedDescription: "Found string '\(str)' in history order, which is not of the expected UUID format.").log(with: warningLogger)
            }
        }
        return uuidOrder
    }
    
    func loadData(forItemWithId id: UUID, andType type: NSPasteboard.PasteboardType) -> Data? {
        do {
            return try dataFileManager.loadData(contentsOf: getUrl(forItemWithId: id, andPasteboardType: type))
        }
        catch {
            YippyError(localizedDescription: "Error: Failed to retrieve data with type \(type.rawValue) for item with id \(id.uuidString) due to error: \(error.localizedDescription)").log(with: self.errorLogger)
            return nil
        }
    }
    
    func loadHistory(cache: HistoryCache) -> History {
        guard let order = loadHistoryOrder() else {
            YippyWarning(localizedDescription: "Failed to retrieve order. Creating new order...").log(with: warningLogger)
            saveHistoryOrder(history: [])
            return History(cache: cache, items: [])
        }
        var items = [UUID: HistoryItem]()
        var contents = [URL]()
        
        do {
            // Get all the items
            contents = try self.fileManager.contentsOfDirectory(at: Constants.urls.history, includingPropertiesForKeys: nil)
            // Remove the history order
            contents.removeAll(where: {$0 == Constants.urls.historyOrder})
            contents.removeAll(where: {$0.lastPathComponent == ".DS_Store"})
        }
        catch {
            let historyError = YippyError(code: 0, userInfo: [
                NSLocalizedDescriptionKey: "Creating an empty history because we failed to load history due to error: \(error.localizedDescription)"
            ])
            historyError.log(with: self.errorLogger)
            historyError.show(with: self.alerter)
            saveHistoryOrder(history: [])
            return History(cache: cache, items: [])
        }
        
        for content in contents {
            // Get the id and build the item
            if let id = UUID(uuidString: content.lastPathComponent) {
                do {
                    // Get all the files
                    var dataUrls = try self.fileManager.contentsOfDirectory(at: content, includingPropertiesForKeys: nil)
                    dataUrls.removeAll(where: { url in
                        let lastPathComponent = url.lastPathComponent
                        return lastPathComponent == HistoryItem.metadataFileName || lastPathComponent == ".DS_Store"
                    })
                    // and create the types
                    let types = dataUrls.map({NSPasteboard.PasteboardType($0.lastPathComponent)})
                    let metadata = self.loadMetadata(forItemWithId: id, availableTypes: types)
                    items[id] = HistoryItem(fsId: id, types: types, cache: cache, metadata: metadata)
                }
                catch {
                    let historyError = YippyError(code: 0, userInfo: [
                        NSLocalizedDescriptionKey: "Failed to load clipboard data for history item with id '\(id.uuidString)' due to error: \(error.localizedDescription). Will continue anyway."
                    ])
                    historyError.log(with: self.errorLogger)
                    historyError.show(with: self.alerter)
                }
            }
            else {
                // Skip
                YippyWarning(localizedDescription: "Directory '\(content.lastPathComponent)' in history directory could not be interpreted as a history item.").log(with: self.warningLogger)
            }
        }
        
        var orderedItems = [HistoryItem]()
        var unfoundItems = [String]()
        for id in order {
            if let item = items.removeValue(forKey: id) {
                orderedItems.append(item)
            }
            else {
                unfoundItems.append(id.uuidString)
            }
        }
        if !unfoundItems.isEmpty {
            let unfound = unfoundItems.map({"'\($0)'"}).joined(separator: ", ")
            let historyError = YippyError(code: 0, userInfo: [
                NSLocalizedDescriptionKey: "We cannot find the saved clipboard items with ids: \(unfound). You may notice them missing from the history."
            ])
            historyError.log(with: self.errorLogger)
            historyError.show(with: self.alerter)
            for unfoundItem in unfoundItems {
                orderedItems.removeAll(where: {$0.fsId.uuidString == unfoundItem})
            }
            saveHistoryOrder(history: orderedItems)
        }
        
        if !items.isEmpty {
            let unfound = items.map({$0.key.uuidString}).joined(separator: ", ")
            let historyError = YippyError(code: 0, userInfo: [
                NSLocalizedDescriptionKey: "We could not find the order for the saved clipboard items with ids: \(unfound). So they will be added to the most recent history."
            ])
            historyError.log(with: self.errorLogger)
            historyError.show(with: self.alerter)
            orderedItems = items.map({$0.value}) + orderedItems
            saveHistoryOrder(history: orderedItems)
        }
        
        return History(cache: cache, items: orderedItems)
    }
    
    func insertItem(newHistory: [HistoryItem], at i: Int, completionHandler handler: ((Bool) -> Void)? = nil) {
        dispatchQueue.async {
            // First check that we have unsaved data to save
            guard let unsavedData = newHistory[i].unsavedData else {
                let historyError = YippyError(code: 0, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to save new item due to error: unsavedError is nil"
                ])
                historyError.log(with: self.errorLogger)
                historyError.show(with: self.alerter)
                self.callHander(handler, withVal: false)
                return
            }
            
            // Create folder for the new item
            let directoryUrl = self.getUrl(forItemWithId: newHistory[i].fsId)
            do {
                try self.fileManager.createDirectory(at: directoryUrl, withIntermediateDirectories: true)
            }
            catch {
                let historyError = YippyError(code: 0, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to save new item due to error: \(error.localizedDescription) Attempted to create directory at '\(directoryUrl.absoluteString)'."
                ])
                historyError.log(with: self.errorLogger)
                historyError.show(with: self.alerter)
                self.callHander(handler, withVal: false)
                return
            }
            
            // Save the data
            for (type, data) in unsavedData {
                let itemUrl = self.getUrl(forItemWithId: newHistory[i].fsId, andPasteboardType: type)
                do {
                    try self.dataFileManager.writeData(data, to: itemUrl, options: Data.WritingOptions())
                }
                catch {
                    let historyError = YippyError(code: 0, userInfo: [
                        NSLocalizedDescriptionKey: "Failed to save new pasteboard item due to error: \(error.localizedDescription) Attempted to save pasteboard item at '\(itemUrl)'."
                    ])
                    historyError.log(with: self.errorLogger)
                    self.callHander(handler, withVal: false)
                    return
                }
            }

            // Start caching now that the data is written
            newHistory[i].startCaching()

            self.saveMetadata(newHistory[i])

            // Update order
            self.saveHistoryOrder(history: newHistory, completionHandler: handler)
        }
    }
    
    func deleteItem(newHistory: [HistoryItem], deleted: HistoryItem, completionHandler handler: ((Bool) -> Void)? = nil) {
        dispatchQueue.async {
            // Delete the folder
            do {
                try self.fileManager.removeItem(at: self.getUrl(forItemWithId: deleted.fsId))
            }
            catch {
                let historyError = YippyError(code: 0, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to delete item due to error: \(error.localizedDescription)"
                ])
                historyError.log(with: self.errorLogger)
                historyError.show(with: self.alerter)
                self.callHander(handler, withVal: false)
                return
            }
            
            // Stop caching the item
            deleted.stopCaching()
            
            // Update order
            self.saveHistoryOrder(history: newHistory, completionHandler: handler)
        }
    }
    
    func reduce(oldHistory: [HistoryItem], toSize size: Int, completionHandler handler: ((Bool) -> Void)? = nil) {
        if oldHistory.count <= size {
            callHander(handler, withVal: true)
            return
        }
        
        dispatchQueue.async {
            let newHistory = Array(oldHistory.prefix(size))
            
            for item in oldHistory.suffix(from: size) {
                do {
                    try self.fileManager.removeItem(at: self.getUrl(forItemWithId: item.fsId))
                }
                catch {
                    let historyError = YippyError(code: 0, userInfo: [
                        NSLocalizedDescriptionKey: "Failed to delete item due to error: \(error.localizedDescription)"
                    ])
                    historyError.log(with: self.errorLogger)
                    historyError.show(with: self.alerter)
                    self.callHander(handler, withVal: false)
                }
                
                item.stopCaching()
            }
            
            // Update order
            self.saveHistoryOrder(history: newHistory, completionHandler: handler)
        }
    }
    
    func moveItem(newHistory: [HistoryItem], from: Int, to: Int, completionHandler: ((Bool) -> Void)? = nil) {
        saveHistoryOrder(history: newHistory, completionHandler: completionHandler)
    }

    func clearHistory(completionHandler handler: ((Bool) -> Void)? = nil) {
        dispatchQueue.async {
            // Delete the old history
            do {
                try self.fileManager.removeItem(at: Constants.urls.history)
            }
            catch {
                let historyError = YippyError(code: 0, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to delete old history due to error: \(error.localizedDescription)"
                ])
                historyError.log(with: self.errorLogger)
                historyError.show(with: self.alerter)
                self.callHander(handler, withVal: false)
                return
            }
            
            // Create a new empty history
            do {
                try self.fileManager.createDirectory(at: Constants.urls.history, withIntermediateDirectories: true)
            }
            catch {
                let historyError = YippyError(code: 0, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to create directory for new history due to error: \(error.localizedDescription)"
                ])
                historyError.log(with: self.errorLogger)
                historyError.show(with: self.alerter)
                self.callHander(handler, withVal: false)
                return
            }
            
            // Save the new order
            self.saveHistoryOrder(history: [], completionHandler: handler)
        }
    }
    
    func getUrl(forItemWithId id: UUID) -> URL {
        return Constants.urls.history.appendingPathComponent("\(id.uuidString)", isDirectory: true)
    }

    func getUrl(forItemWithId id: UUID, andPasteboardType type: NSPasteboard.PasteboardType) -> URL {
        return getUrl(forItemWithId: id).appendingPathComponent(type.rawValue, isDirectory: false)
    }

    private func metadataUrl(forItemWithId id: UUID) -> URL {
        return getUrl(forItemWithId: id).appendingPathComponent(HistoryItem.metadataFileName, isDirectory: false)
    }

    private func readMetadata(forItemWithId id: UUID) -> HistoryItem.Metadata? {
        let url = metadataUrl(forItemWithId: id)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        do {
            let data = try dataFileManager.loadData(contentsOf: url)
            return try JSONDecoder().decode(HistoryItem.Metadata.self, from: data)
        }
        catch {
            let warning = YippyWarning(localizedDescription: "Failed to read metadata for history item with id '\(id.uuidString)' due to error: \(error.localizedDescription)")
            warning.log(with: warningLogger)
            return nil
        }
    }

    private func loadMetadata(forItemWithId id: UUID, availableTypes: [NSPasteboard.PasteboardType]) -> HistoryItem.Metadata {
        if let metadata = readMetadata(forItemWithId: id) {
            return metadata
        }

        let inferredMetadata = HistoryItem.Metadata.infer(
            types: availableTypes,
            dataProvider: { [weak self] type in
                guard let self = self else { return nil }
                let url = self.getUrl(forItemWithId: id, andPasteboardType: type)
                return try? self.dataFileManager.loadData(contentsOf: url)
            },
            originBundleId: nil
        )
        save(metadata: inferredMetadata, forItemWithId: id)
        return inferredMetadata
    }

    @discardableResult
    private func saveMetadata(_ item: HistoryItem) -> Bool {
        save(metadata: item.metadata, forItemWithId: item.fsId)
    }

    @discardableResult
    private func save(metadata: HistoryItem.Metadata, forItemWithId id: UUID) -> Bool {
        let url = metadataUrl(forItemWithId: id)

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(metadata)
            try dataFileManager.writeData(data, to: url, options: .atomic)
            return true
        }
        catch {
            let warning = YippyWarning(localizedDescription: "Failed to save metadata for history item with id '\(id.uuidString)' due to error: \(error.localizedDescription)")
            warning.log(with: warningLogger)
            return false
        }
    }
}
