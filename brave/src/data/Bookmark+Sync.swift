/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. 
 If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import CoreData
import Shared
import JavaScriptCore

private let log = Logger.browserLogger

// Sync related methods for Bookmark model.
extension Bookmark {
    /// Sets order for all bookmarks. Needed after user joins sync group for the first time.
    class func setSyncOrderForAll(parentFolder: Bookmark? = nil) {
        var predicate: NSPredicate?
        
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
            if bookmark.syncOrder != nil {
                continue
            }
            
            if let parent = parentFolder, let syncOrder = parent.syncOrder {
                let order = syncOrder + ".\(counter)"
                bookmark.syncOrder = order
            } else {
                let order = baseOrder + "\(counter)"
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
    
    private class func maxBookmarkSyncOrder(parent: Bookmark?, context: NSManagedObjectContext) -> String? {
        var predicate: NSPredicate?
        
        if let parent = parent {
            predicate = NSPredicate(format: "parentFolder == %@ AND isFavorite == NO", parent)
        } else {
            predicate = NSPredicate(format: "parentFolder == nil AND isFavorite == NO")
        }
        
        guard let allBookmarks = Bookmark.get(predicate: predicate, context: context) as? [Bookmark] else {
            return nil
        }
        
        if allBookmarks.isEmpty { return nil }
        
        // New bookmarks are sometimes added to context before this method is called.
        // We needd to filter out bookmarks with empty sync orders.
        let highestOrderBookmark = allBookmarks.filter { $0.syncOrder != nil }.max { a, b in
            guard let aOrder = a.syncOrder, let bOrder = b.syncOrder else { return false } // Should never be nil at this point
            
            return aOrder < bOrder
        }
        
        return highestOrderBookmark?.syncOrder
    }
    
    func setLastSyncOrder(context: NSManagedObjectContext) {
        let lastBookmarkOrder = Bookmark.maxBookmarkSyncOrder(parent: parentFolder, context: context)
        
        // The sync lib javascript method doesn't handle cases when there are no other bookmarks on a given level.
        // We need to do it locally, there are 3 cases:
        // 1. At least one bookmark is present at a given level -> we do the JS call
        // 2. Root level, no bookmarks added -> need to use baseOrder 
        // 3. Nested folder, no bookmarks -> need to get parent folder syncOrder
        if lastBookmarkOrder == nil && parentFolder == nil {
            syncOrder = Bookmark.baseOrder + "1"
        } else if let parentOrder = parentFolder?.syncOrder, lastBookmarkOrder == nil {
            syncOrder = parentOrder + ".1"
        } else {
            syncOrder = Sync.shared.getBookmarkOrder(previousOrder: lastBookmarkOrder, nextOrder: nil)
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
        let allBookmarks = getAllBookmarks(context: context)
        
        allBookmarks.forEach { bookmark in
            bookmark.syncOrder = nil
            // TODO: Clear syncUUIDs
//            bookmark.syncUUID = nil
        }
        
        DataController.saveContext(context: context)
        Sync.shared.baseSyncOrder = nil
    }
}
