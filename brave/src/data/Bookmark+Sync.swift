/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. 
 If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import CoreData
import Shared
import JavaScriptCore

private let log = Logger.browserLogger

// Sync related methods for Bookmark model.
extension Bookmark {
    /// Sets proper order for all bookmarks. Needed after user joins sync group for a first time.
    class func setSyncOrderForAll(parentFolder: Bookmark? = nil) {
        var predicate: NSPredicate?
        
        guard let baseSyncOrder = Sync.shared.baseSyncOrder else { return }
        
        print("base sync order: \(baseSyncOrder)")
        
        if let parentFolder = parentFolder {
            predicate = NSPredicate(format: "parentFolder == %@ AND isFavorite == NO", parentFolder)
        } else {
            predicate = NSPredicate(format: "parentFolder == nil AND isFavorite == NO")
        }
        
        let orderSort = NSSortDescriptor(key:"order", ascending: true)
        let createdSort = NSSortDescriptor(key:"created", ascending: false)
        
        let sort = [orderSort, createdSort]
        
        let context = DataController.shared.workerContext
        guard let allBookmarks = get(predicate: predicate, sortDescriptors: sort,  context: context) as? [Bookmark] else {
            return
        }
        
        var counter = 1
        
        for bookmark in allBookmarks {
            if bookmark.syncOrder != nil { continue }
            
            // set order
            if let parent = parentFolder, let syncOrder = parent.syncOrder {
                let order = syncOrder + ".\(counter)"
                bookmark.syncOrder = order
            } else {
                let order = baseSyncOrder + "\(counter)"
                bookmark.syncOrder = order
            }
            
            counter += 1
            
            // Calling this method recursively to get ordering for nested bookmarks
            if bookmark.isFolder {
                setSyncOrderForAll(parentFolder: bookmark)
            }
        }
        
        DataController.saveContext(context: context)
    }
    
    
    func setSyncOrder(context: NSManagedObjectContext) {
        guard let baseOrder = Sync.shared.baseSyncOrder else  { return } 
        
        let previousOrder = getBookmarkWith(prevOrNext: .previous, orderToGet: order)?.syncOrder
        let nextOrder = getBookmarkWith(prevOrNext: .next, orderToGet: order)?.syncOrder
        
        // The sync lib javascript method doesn't handle cases when there are no other bookmarks on a given level.
        // We need to do it locally, there are 3 cases:
        // 1. At least one bookmark is present at a given level -> we do the JS call
        // 2. Root level, no bookmarks added -> need to use baseSyncOrder 
        // 3. Nested folder, no bookmarks -> need to get parent folder syncOrder
        if previousOrder == nil && nextOrder == nil && parentFolder == nil {
            syncOrder = baseOrder + "1"
        } else if let parentOrder = parentFolder?.syncOrder, previousOrder == nil, nextOrder == nil {
            syncOrder = parentOrder + ".1"
        } else {
            syncOrder = Sync.getBookmarkOrder(previousOrder: previousOrder, nextOrder: nextOrder)
        }
        
        DataController.saveContext(context: context)
    }
    
    enum BookmarkNeighbour { case previous, next }
    
    func getBookmarkWith(prevOrNext: BookmarkNeighbour, orderToGet: Int16) -> Bookmark? {
        var predicate: NSPredicate?
        let orderParam = prevOrNext == .previous ? orderToGet - 1 : orderToGet + 1
        
        if let parentFolder = parentFolder {
            predicate = NSPredicate(format: "parentFolder == %@ AND isFavorite == NO AND order == \(orderParam)", parentFolder)
        } else {
            predicate = NSPredicate(format: "parentFolder == nil AND isFavorite == NO AND order == \(orderParam)")
        }
        
        let context = DataController.shared.workerContext
        
        guard let foundBookmark = Bookmark.get(predicate: predicate, context: context)?.first as? Bookmark else {
            // Edge case, first bookmark in a nested folder. We do not have any info about prev and next,
            // need to look at the parent folder
            return parentFolder
        }
        
        return foundBookmark
    }
    
    class func removeSyncOrders() {
        let context = DataController.shared.workerContext
        
        // FIXME: Use something better than hardocded strings
        let updateRequest = NSBatchUpdateRequest(entityName: "Bookmark")
        updateRequest.predicate = NSPredicate(format: "isFavorite == NO")
        updateRequest.propertiesToUpdate = ["syncOrder": NSExpression(forConstantValue: nil)]
        
        Sync.shared.baseSyncOrder = nil
        
        do {
            try context.execute(updateRequest)
        } catch {
            log.error("Failed to remove syncOrder")
        }
    }
}
