/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. 
 If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import CoreData
import Shared

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
        
        var counter = 0
        
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
        var predicate: NSPredicate?
        
        guard let baseSyncOrder = Sync.shared.baseSyncOrder else { return }
        if syncOrder != nil { return }
        
        if let parent = parentFolder {
            predicate = NSPredicate(format: "parentFolder == %@ AND isFavorite == NO", parent)
        } else {
            predicate = NSPredicate(format: "parentFolder == nil AND isFavorite == NO")
        }
        
        guard let allBookmarks = Bookmark.get(predicate: predicate, context: context) as? [Bookmark] else {
            return
        }
        
        // There are 3 cases to consider while initializing a sync order for new bookmarks:
        // 1. Root level, no other bookmarks added - we're setting sync base order + 0
        // 2. Nested folder, no other bookmarks added - taking parent folder sync ordder and adding .0
        // 3. At least 1 bookmark is present at given level, taking the highest sync order out of all bookmarks of a level
        // and incrementing last bit by 1.
        if parentFolder == nil && allBookmarks.count < 2 {
            syncOrder = "\(baseSyncOrder)0"
        } else if let parent = parentFolder, let parentSyncOrder = parent.syncOrder, allBookmarks.count < 2 {
            syncOrder = "\(parentSyncOrder).0"
        } else {
            // First bookmark is created with order 0
            // We don't check for empty bookmarks array because the new bookmark is already added into context.
            
            guard var maxSyncOrder = (allBookmarks.map { $0.syncOrder ?? "" }.max()) else { return }
            guard let lastNumber = maxSyncOrder.split(separator: ".").last else { return }
            
            guard let number = Int(lastNumber) else { return }
            
            maxSyncOrder.replaceSubrange(lastNumber.startIndex..<lastNumber.endIndex, with: "\(number + 1)")
            
            syncOrder = maxSyncOrder
        }
        
        DataController.saveContext(context: context)
    }
    
    class func removeSyncOrders() {
        let context = DataController.shared.workerContext
        
        // FIXME: Use something better than hardocded strings
        let updateRequest = NSBatchUpdateRequest(entityName: "Bookmark")
        updateRequest.predicate = NSPredicate(format: "isFavorite == NO")
        updateRequest.propertiesToUpdate = ["syncOrder": NSExpression(forConstantValue: nil)]
        
        do {
            try context.execute(updateRequest)
        } catch {
            log.error("Failed to remove syncOrder")
        }
    }
}
