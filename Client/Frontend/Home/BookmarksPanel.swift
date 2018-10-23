/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import CoreData
import Shared
import XCGLogger
import Eureka
import Storage

private let log = Logger.browserLogger

// MARK: - UX constants.

struct BookmarksPanelUX {
    fileprivate static let BookmarkFolderHeaderViewChevronInset: CGFloat = 10
    fileprivate static let BookmarkFolderChevronSize: CGFloat = 20
    fileprivate static let BookmarkFolderChevronLineWidth: CGFloat = 4.0
    fileprivate static let BookmarkFolderTextColor = UIColor(red: 92/255, green: 92/255, blue: 92/255, alpha: 1.0)
    fileprivate static let WelcomeScreenPadding: CGFloat = 15
    fileprivate static let WelcomeScreenItemTextColor = UIColor.gray
    fileprivate static let WelcomeScreenItemWidth = 170
    fileprivate static let SeparatorRowHeight: CGFloat = 0.5
}

public extension UIBarButtonItem {
    
    public class func createImageButtonItem(_ image:UIImage, action:Selector) -> UIBarButtonItem {
        let button = UIButton(type: .custom)
        button.frame = CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height)
        button.addTarget(self, action: action, for: .touchUpInside)
        button.setImage(image, for: .normal)
        
        return UIBarButtonItem(customView: button)
    }
    
    public class func createFixedSpaceItem(_ width:CGFloat) -> UIBarButtonItem {
        let item = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: self, action: nil)
        item.width = width
        return item
    }
}

class BkPopoverControllerDelegate : NSObject, UIPopoverPresentationControllerDelegate {
    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        return .none;
    }
}

class BorderedButton: UIButton {
    let buttonBorderColor = UIColor.lightGray
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        layer.borderColor = buttonBorderColor.cgColor
        layer.borderWidth = 0.5
        
        contentEdgeInsets = UIEdgeInsets(top: 7, left: 10, bottom: 7, right: 10)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("not implemented")
    }
    
    override var isHighlighted: Bool {
        didSet {
            let fadedColor = buttonBorderColor.withAlphaComponent(0.2).cgColor
            
            if isHighlighted {
                layer.borderColor = fadedColor
            } else {
                layer.borderColor = buttonBorderColor.cgColor
                
                let animation = CABasicAnimation(keyPath: "borderColor")
                animation.fromValue = fadedColor
                animation.toValue = buttonBorderColor.cgColor
                animation.duration = 0.4
                layer.add(animation, forKey: "")
            }
        }
    }
}

struct FolderPickerRow : Equatable {
    var folder: Bookmark?
}
func ==(lhs: FolderPickerRow, rhs: FolderPickerRow) -> Bool {
    return lhs.folder === rhs.folder
}

class BookmarkEditingViewController: FormViewController {
    var completionBlock:((_ controller:BookmarkEditingViewController) -> Void)?

    var folders = [Bookmark]()
    
    var bookmarksPanel:BookmarksPanel!
    var bookmark:Bookmark!
    var bookmarkIndexPath:IndexPath!

    let BOOKMARK_TITLE_ROW_TAG:String = "BOOKMARK_TITLE_ROW_TAG"
    let BOOKMARK_URL_ROW_TAG:String = "BOOKMARK_URL_ROW_TAG"
    let BOOKMARK_FOLDER_ROW_TAG:String = "BOOKMARK_FOLDER_ROW_TAG"

    var titleRow:TextRow?
    var urlRow: URLRow?
    
    init(bookmarksPanel: BookmarksPanel, indexPath: IndexPath, bookmark: Bookmark) {
        super.init(nibName: nil, bundle: nil)

        self.bookmark = bookmark
        self.bookmarksPanel = bookmarksPanel
        self.bookmarkIndexPath = indexPath

        // get top-level folders
        folders = Bookmark.getFolders(bookmark: nil, context: DataController.viewContext)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        //called when we're about to be popped, so use this for callback
        if let block = self.completionBlock {
            block(self)
        }
        
        self.bookmark.update(customTitle: self.titleRow?.value, url: self.urlRow?.value?.absoluteString, save: true)
    }
    
    var isEditingFolder:Bool {
        return bookmark.isFolder
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        let firstSectionName = !isEditingFolder ?  Strings.Bookmark_Info : Strings.Bookmark_Folder

        let nameSection = Section(firstSectionName)
            
        nameSection <<< TextRow() { row in
            row.tag = BOOKMARK_TITLE_ROW_TAG
            row.title = Strings.Name
            row.value = bookmark.displayTitle
            self.titleRow = row
        }

        form +++ nameSection
        
        // Only show URL option for bookmarks, not folders
        if !isEditingFolder {
            nameSection <<< URLRow() { row in
                row.tag = BOOKMARK_URL_ROW_TAG
                row.title = Strings.URL
                row.value = URL(string: bookmark.url ?? "")
                self.urlRow = row
            }
        }

        // Currently no way to edit bookmark/folder locations
        // See de9e1cc for removal of this logic
    }
}

class BookmarksPanel: SiteTableViewController, HomePanel {
    weak var homePanelDelegate: HomePanelDelegate? = nil
    var bookmarksFRC: NSFetchedResultsController<Bookmark>?

    fileprivate let BookmarkFolderCellIdentifier = "BookmarkFolderIdentifier"
    //private let BookmarkSeparatorCellIdentifier = "BookmarkSeparatorIdentifier"
    fileprivate let BookmarkFolderHeaderViewIdentifier = "BookmarkFolderHeaderIdentifier"

    var editBookmarksToolbar:UIToolbar!
    var editBookmarksButton:UIBarButtonItem!
    var addFolderButton: UIBarButtonItem?
    weak var addBookmarksFolderOkAction: UIAlertAction?
  
    var isEditingIndividualBookmark:Bool = false
    
    weak var delegate: MainSidePanelViewControllerDelegate?

    var currentFolder: Bookmark? = nil

    init() {
        super.init(nibName: nil, bundle: nil)
        self.title = Strings.Bookmarks
        // NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(BookmarksPanel.notificationReceived(_:)), name: NotificationFirefoxAccountChanged, object: nil)

        // self.tableView.registerClass(SeparatorTableCell.self, forCellReuseIdentifier: BookmarkSeparatorCellIdentifier)
        self.tableView.register(BookmarkFolderTableViewCell.self, forCellReuseIdentifier: BookmarkFolderCellIdentifier)
        self.tableView.register(BookmarkFolderTableViewHeader.self, forHeaderFooterViewReuseIdentifier: BookmarkFolderHeaderViewIdentifier)
    }
    
    convenience init(folder: Bookmark?) {
        self.init()
        
        self.currentFolder = folder
        self.title = folder?.displayTitle ?? Strings.Bookmarks
        self.bookmarksFRC = Bookmark.frc(parentFolder: folder)
        self.bookmarksFRC?.delegate = self
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.reloadData), name: NotificationMainThreadContextSignificantlyChanged, object: nil)
        
        Sync.shared.addFetchedHandler { [weak self] in
            self?.reloadData()
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
    
        self.view.backgroundColor = BraveUX.BackgroundColorForSideToolbars
        
        tableView.allowsSelectionDuringEditing = true
        
        let navBar = self.navigationController?.navigationBar
        navBar?.barTintColor = BraveUX.BackgroundColorForSideToolbars
        navBar?.isTranslucent = false
        navBar?.titleTextAttributes = [NSAttributedStringKey.font : UIFont.systemFont(ofSize: UIConstants.DefaultChromeSize, weight: UIFont.Weight.medium), NSAttributedStringKey.foregroundColor : BraveUX.GreyJ]
        navBar?.clipsToBounds = true
        
        let width = self.view.bounds.size.width
        let toolbarHeight = CGFloat(44)
        
        editBookmarksToolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: width, height: toolbarHeight))
        createEditBookmarksToolbar()
        editBookmarksToolbar.barTintColor = BraveUX.BackgroundColorForSideToolbars
        editBookmarksToolbar.isTranslucent = false
        
        self.view.addSubview(editBookmarksToolbar)
        
        editBookmarksToolbar.snp.makeConstraints { make in
            make.height.equalTo(toolbarHeight)
            make.left.equalTo(self.view)
            make.right.equalTo(self.view)
            if #available(iOS 11.0, *) {
                make.bottom.equalTo(self.view).inset(getApp().window!.safeAreaInsets.bottom)
            } else {
                make.bottom.equalTo(self.view)
            }
        }
        
        tableView.snp.makeConstraints { make in
            make.bottom.equalTo(self.view).inset(UIEdgeInsetsMake(0, 0, toolbarHeight, 0))
        }
        
        reloadData()
    }

    @objc override func reloadData() {

        do {
            try self.bookmarksFRC?.performFetch()
        } catch let error as NSError {
            print(error.description)
        }

        super.reloadData()
    }
    
    func disableTableEditingMode() {
        switchTableEditingMode(true)
    }

    
    func switchTableEditingMode(_ forceOff:Bool = false) {
        let editMode:Bool = forceOff ? false : !tableView.isEditing
        tableView.setEditing(editMode, animated: forceOff ? false : true)
        
        updateEditBookmarksButton(editMode)
        resetCellLongpressGesture(tableView.isEditing)
        
        addFolderButton?.isEnabled = !editMode
    }
    
    func updateEditBookmarksButton(_ tableIsEditing:Bool) {
        self.editBookmarksButton.title = tableIsEditing ? Strings.Done : Strings.Edit
        self.editBookmarksButton.style = tableIsEditing ? .done : .plain
    }
    
    func resetCellLongpressGesture(_ editing: Bool) {
        for cell in self.tableView.visibleCells {
            cell.gestureRecognizers?.forEach { cell.removeGestureRecognizer($0) }
            if editing == false {
                let lp = UILongPressGestureRecognizer(target: self, action: #selector(longPressOnCell))
                cell.addGestureRecognizer(lp)
            }
        }
    }

    func createEditBookmarksToolbar() {
        var items = [UIBarButtonItem]()
        
        items.append(UIBarButtonItem.createFixedSpaceItem(5))

        addFolderButton = UIBarButtonItem(image: UIImage(named: "bookmarks_newfolder_icon")?.withRenderingMode(.alwaysTemplate), style: .plain, target: self, action: #selector(onAddBookmarksFolderButton))
        items.append(addFolderButton!)
        
        items.append(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: self, action: nil))

        editBookmarksButton = UIBarButtonItem(image: UIImage(named: "edit")?.withRenderingMode(.alwaysTemplate), style: .plain, target: self, action: #selector(onEditBookmarksButton))
        items.append(editBookmarksButton)
        items.append(UIBarButtonItem.createFixedSpaceItem(5))
        
        items.forEach { $0.tintColor = BraveUX.LightBlue }
        
        editBookmarksToolbar.items = items
        
        // This removes the small top border from the toolbar
        editBookmarksToolbar.clipsToBounds = true
    }
    
    func onDeleteBookmarksFolderButton() {
        guard let currentFolder = currentFolder else {
            NSLog("Delete folder button pressed but no folder object exists (probably at root), ignoring.")
            return
        }

        // TODO: Needs to be recursive
        currentFolder.remove(save: true)

        self.navigationController?.popViewController(animated: true)
    }

    @objc func onAddBookmarksFolderButton() {
        
        let alert = UIAlertController.userTextInputAlert(title: Strings.NewFolder, message: Strings.EnterFolderName) {
            input, _ in
            if let input = input, !input.isEmpty {
                self.addFolder(titled: input)
            }
        }
        self.present(alert, animated: true) {}
    }

    func addFolder(titled title: String) {
        Bookmark.add(url: nil, title: nil, customTitle: title, parentFolder: currentFolder, isFolder: true)
        tableView.setContentOffset(CGPoint.zero, animated: true)
    }
    
    @objc func onEditBookmarksButton() {
        switchTableEditingMode()
    }
    
    func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        // Using the same reorder logic as in FavoritesDataSource
        Bookmark.reorderBookmarks(frc: bookmarksFRC, sourceIndexPath: sourceIndexPath, destinationIndexPath: destinationIndexPath)
        tableView.reloadData()
    }
    
    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        return true
    }
    
    func notificationReceived(_ notification: Notification) {
        switch notification.name {
        case NotificationFirefoxAccountChanged:
            self.reloadData()
            break
        case NSNotification.Name.UITextFieldTextDidChange:
            if let okAction = addBookmarksFolderOkAction, let textField = notification.object as? UITextField {
                okAction.isEnabled = (textField.text?.count ?? 0) > 0
            }
            break
        default:
            // no need to do anything at all
            log.warning("Received unexpected notification \(notification.name)")
            break
        }
    }

    func currentBookmarksPanel() -> BookmarksPanel {
        guard let controllers = navigationController?.viewControllers.filter({ $0 as? BookmarksPanel != nil }) else {
            return self
        }
        return controllers.last as? BookmarksPanel ?? self
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return bookmarksFRC?.fetchedObjects?.count ?? 0
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = super.tableView(tableView, cellForRowAt: indexPath)
        configureCell(cell, atIndexPath: indexPath)
        return cell
    }

    override func getLongPressUrl(forIndexPath indexPath: IndexPath) -> (URL?, [Int]?) {
        guard let obj = bookmarksFRC?.object(at: indexPath) else { return (nil, nil) }
        return (obj.url != nil ? URL(string: obj.url!) : nil, obj.isFolder ? obj.syncUUID : nil)
    }

    fileprivate func configureCell(_ cell: UITableViewCell, atIndexPath indexPath: IndexPath) {

        guard let item = bookmarksFRC?.object(at: indexPath) else { return }
        cell.tag = item.objectID.hashValue

        func configCell(image: UIImage? = nil, icon: FaviconMO? = nil, longPressForContextMenu: Bool = false) {
            if longPressForContextMenu && !tableView.isEditing {
                cell.gestureRecognizers?.forEach { cell.removeGestureRecognizer($0) }
                let lp = UILongPressGestureRecognizer(target: self, action: #selector(longPressOnCell))
                cell.addGestureRecognizer(lp)
            }
            
            cell.imageView?.contentMode = .scaleAspectFit
            cell.imageView?.image = FaviconFetcher.defaultFavicon
            cell.imageView?.layer.cornerRadius = 6
            cell.imageView?.layer.masksToBounds = true
            
            if let image = image {
                // folder or preset icon
                cell.imageView?.image = image
                cell.imageView?.contentMode = .center
            }
            else if let faviconMO = item.domain?.favicon, let urlString = faviconMO.url, let url = URL(string: urlString), let bookmarkUrlString = item.url, let bookmarkUrl = URL(string: bookmarkUrlString) {
                // favicon object associated through domain relationship - set from cache or download
                setCellImage(cell, iconUrl: url, cacheWithUrl: bookmarkUrl)
            }
            else if let urlString = item.url, let bookmarkUrl = URL(string: urlString) {
                if ImageCache.shared.hasImage(bookmarkUrl, type: .square) {
                    // no relationship - check cache for icon which may have been stored recently for url.
                    ImageCache.shared.image(bookmarkUrl, type: .square, callback: { (image) in
                        postAsyncToMain {
                            cell.imageView?.image = image
                        }
                    })
                }
                else {
                    // no relationship - attempt to resolove domain problem
                    let context = DataController.viewContext
                    if let domain = Domain.getOrCreateForUrl(bookmarkUrl, context: context), let faviconMO = domain.favicon, let urlString = faviconMO.url, let url = URL(string: urlString) {
                        postAsyncToMain {
                            self.setCellImage(cell, iconUrl: url, cacheWithUrl: bookmarkUrl)
                        }
                    }
                    else {
                        // last resort - download the icon
                        downloadFaviconsAndUpdateForUrl(bookmarkUrl, indexPath: indexPath)
                    }
                }
            }
        }
        
        let fontSize: CGFloat = 14.0
        cell.textLabel?.text = item.displayTitle ?? item.url
        cell.textLabel?.lineBreakMode = .byTruncatingTail
        
        cell.contentView.backgroundColor = .white
        
        if !item.isFolder {
            configCell(icon: item.domain?.favicon, longPressForContextMenu: true)
            cell.textLabel?.font = UIFont.systemFont(ofSize: fontSize)
            cell.accessoryType = .none
        } else {
            configCell(image: UIImage(named: "bookmarks_folder_hollow"))
            cell.textLabel?.font = UIFont.boldSystemFont(ofSize: fontSize)
            cell.accessoryType = .disclosureIndicator
            if let twoLineCell = cell as? TwoLineTableViewCell {
                twoLineCell.setRightBadge(nil)
            }
        }
    }
    
    fileprivate func downloadFaviconsAndUpdateForUrl(_ url: URL, indexPath: IndexPath) {
        weak var weakSelf = self
        FaviconFetcher.getForURL(url).uponQueue(DispatchQueue.main) { result in
            guard let favicons = result.successValue, favicons.count > 0, let foundIconUrl = favicons.first?.url.asURL, let cell = weakSelf?.tableView.cellForRow(at: indexPath) else { return }
            self.setCellImage(cell, iconUrl: foundIconUrl, cacheWithUrl: url)
        }
    }
    
    fileprivate func setCellImage(_ cell: UITableViewCell, iconUrl: URL, cacheWithUrl: URL) {
        ImageCache.shared.image(cacheWithUrl, type: .square, callback: { (image) in
            if image != nil {
                postAsyncToMain {
                    cell.imageView?.image = image
                }
            }
            else {
                cell.imageView?.setFaviconImage(with: iconUrl, cacheUrl: cacheWithUrl)
            }
        })
    }
    
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if let cell = cell as? BookmarkFolderTableViewCell {
            cell.textLabel?.font = DynamicFontHelper.defaultHelper.DeviceFontHistoryPanel
        }
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        
        #if NO_SYNC
            return nil
        #endif
        
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14, weight: UIFont.Weight.regular)
        label.textAlignment = .center
        
        if Sync.shared.isInSyncGroup {
            label.textColor = BraveUX.GreyG
            
            if Sync.shared.lastFetchedRecordTimestamp != nil {
                label.text = Strings.Syncing
            }
        } else {
            label.textColor = BraveUX.LightBlue
            label.numberOfLines = 2
            label.text = Strings.SyncBookmarksCallout
        }
        
        let view = UIView()
        view.backgroundColor = BraveUX.White
        view.layer.shadowOffset = CGSize.zero
        view.layer.shadowColor = BraveUX.GreyD.cgColor
        view.layer.shadowRadius = 1
        view.layer.shadowOpacity = 1
        
        let headerTapGesture = UITapGestureRecognizer(target: self, action: #selector(tapSyncHeader))
        view.addSubview(label)
        view.addGestureRecognizer(headerTapGesture)
        
        label.snp.makeConstraints { make in
            make.margins.equalTo(view)
        }
        
        return view
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return super.tableView(tableView, heightForRowAt: indexPath)
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        #if NO_SYNC
            return 0
        #endif
        
        // Only display sync header on root
        if currentFolder != nil {
            return 0
        }
        
        // Sync is connected but nothing is being synced.
        if Sync.shared.isInSyncGroup && Sync.shared.lastFetchedRecordTimestamp == nil {
            return 0
        }
        
        return Sync.shared.isInSyncGroup ? 28 : 58
    }
    
    func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        return indexPath
    }
    
    @objc func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        guard let bookmark = bookmarksFRC?.object(at: indexPath) else { return false }
        
        return !bookmark.isFavorite
    }

    @objc func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)

        guard let bookmark = bookmarksFRC?.object(at: indexPath) else { return }

        if !bookmark.isFolder {
            if tableView.isEditing {
                //show editing view for bookmark item
                self.showEditBookmarkController(tableView, indexPath: indexPath)
            }
            else {
                if let url = URL(string: bookmark.url ?? "") {
                    homePanelDelegate?.homePanel(self, didSelectURL: url)
                }
            }
        } else {
            if tableView.isEditing {
                //show editing view for bookmark item
                self.showEditBookmarkController(tableView, indexPath: indexPath)
            }
            else {
                let nextController = BookmarksPanel(folder: bookmark)
                nextController.homePanelDelegate = self.homePanelDelegate
                
                self.navigationController?.pushViewController(nextController, animated: true)
            }
        }
    }
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        // Intentionally blank. Required to use UITableViewRowActions
    }

    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCellEditingStyle {
        return .delete
    }
    
    @objc func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
        guard let item = bookmarksFRC?.object(at: indexPath) else { return nil }

        let deleteAction = UITableViewRowAction(style: UITableViewRowActionStyle.destructive, title: Strings.Delete, handler: { (action, indexPath) in

            func delete() {
                item.remove(save: true)
                
                // Updates the bookmark state
                getApp().browserViewController.updateURLBarDisplayURL(tab: nil)
            }
            
            if let children = item.children, !children.isEmpty {
                let alert = UIAlertController(title: "Delete Folder?", message: "This will delete all folders and bookmarks inside. Are you sure you want to continue?", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Cancel", style: UIAlertActionStyle.cancel, handler: nil))
                alert.addAction(UIAlertAction(title: "Yes, Delete", style: UIAlertActionStyle.destructive) { action in
                    delete()
                    })
               
                self.present(alert, animated: true, completion: nil)
            } else {
                delete()
            }
        })

        let editAction = UITableViewRowAction(style: UITableViewRowActionStyle.normal, title: Strings.Edit, handler: { (action, indexPath) in
            self.showEditBookmarkController(tableView, indexPath: indexPath)
        })

        return [deleteAction, editAction]
    }
    
    fileprivate func showEditBookmarkController(_ tableView: UITableView, indexPath:IndexPath) {
        guard let item = bookmarksFRC?.object(at: indexPath), !item.isFavorite else { return }
        let nextController = BookmarkEditingViewController(bookmarksPanel: self, indexPath: indexPath, bookmark: item)

        nextController.completionBlock = { controller in
            self.isEditingIndividualBookmark = false
        }
        self.isEditingIndividualBookmark = true
        self.navigationController?.pushViewController(nextController, animated: true)
    }
    
    @objc func tapSyncHeader() {
        delegate?.openSyncSetup()
    }
}

private protocol BookmarkFolderTableViewHeaderDelegate {
    func didSelectHeader()
}

extension BookmarksPanel: BookmarkFolderTableViewHeaderDelegate {
    fileprivate func didSelectHeader() {
        self.navigationController?.popViewController(animated: true)
    }
}

class BookmarkFolderTableViewCell: TwoLineTableViewCell {
    fileprivate let ImageMargin: CGFloat = 12

    override init(style: UITableViewCellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        textLabel?.backgroundColor = UIColor.clear
        textLabel?.tintColor = BookmarksPanelUX.BookmarkFolderTextColor

        imageView?.image = UIImage(named: "bookmarkFolder")

        self.editingAccessoryType = .disclosureIndicator

        separatorInset = UIEdgeInsets.zero
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

fileprivate class BookmarkFolderTableViewHeader : UITableViewHeaderFooterView {
    var delegate: BookmarkFolderTableViewHeaderDelegate?

    lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.textColor = UIConstants.HighlightBlue
        return label
    }()

    lazy var chevron: ChevronView = {
        let chevron = ChevronView(direction: .left)
        chevron.tintColor = UIConstants.HighlightBlue
        chevron.lineWidth = BookmarksPanelUX.BookmarkFolderChevronLineWidth
        return chevron
    }()

    lazy var topBorder: UIView = {
        let view = UIView()
        view.backgroundColor = SiteTableViewControllerUX.HeaderBorderColor
        return view
    }()

    lazy var bottomBorder: UIView = {
        let view = UIView()
        view.backgroundColor = SiteTableViewControllerUX.HeaderBorderColor
        return view
    }()

    override var textLabel: UILabel? {
        return titleLabel
    }

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)

        isUserInteractionEnabled = true

        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(BookmarkFolderTableViewHeader.viewWasTapped(_:)))
        tapGestureRecognizer.numberOfTapsRequired = 1
        addGestureRecognizer(tapGestureRecognizer)

        addSubview(topBorder)
        addSubview(bottomBorder)
        contentView.addSubview(chevron)
        contentView.addSubview(titleLabel)

        chevron.snp.makeConstraints { make in
            make.left.equalTo(contentView).offset(BookmarksPanelUX.BookmarkFolderHeaderViewChevronInset)
            make.centerY.equalTo(contentView)
            make.size.equalTo(BookmarksPanelUX.BookmarkFolderChevronSize)
        }

        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(chevron.snp.right).offset(BookmarksPanelUX.BookmarkFolderHeaderViewChevronInset)
            make.right.greaterThanOrEqualTo(contentView).offset(-BookmarksPanelUX.BookmarkFolderHeaderViewChevronInset)
            make.centerY.equalTo(contentView)
        }

        topBorder.snp.makeConstraints { make in
            make.left.right.equalTo(self)
            make.top.equalTo(self).offset(-0.5)
            make.height.equalTo(0.5)
        }

        bottomBorder.snp.makeConstraints { make in
            make.left.right.bottom.equalTo(self)
            make.height.equalTo(0.5)
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc fileprivate func viewWasTapped(_ gestureRecognizer: UITapGestureRecognizer) {
        delegate?.didSelectHeader()
    }
}

extension BookmarksPanel : NSFetchedResultsControllerDelegate {
    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.beginUpdates()
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
       tableView.endUpdates()
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        switch (type) {
        case .update:
            guard let indexPath = indexPath, let cell = tableView.cellForRow(at: indexPath) else {
                return
            }
            configureCell(cell, atIndexPath: indexPath)
       case .insert:
            guard let path = newIndexPath else {
                return
            }
            tableView.insertRows(at: [path], with: .automatic)
        case .delete:
            guard let indexPath = indexPath else {
                return
            }
            tableView.deleteRows(at: [indexPath], with: .automatic)
        case .move:
            guard let indexPath = indexPath, let newIndexPath = newIndexPath else { return }
            tableView.moveRow(at: indexPath, to: newIndexPath)
        }
    }
}
