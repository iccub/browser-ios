/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import Shared
import XCGLogger
import Storage
import WebImage
import Deferred

private let log = Logger.browserLogger

struct TopSitesPanelUX {
    static let statsHeight: CGFloat = 110.0
    static let statsBottomMargin: CGFloat = 5
}

class TopSitesPanel: UIViewController, HomePanel {
    weak var homePanelDelegate: HomePanelDelegate?

    // MARK: - Favorites collection view properties
    fileprivate lazy var collection: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 6

        let view = UICollectionView(frame: self.view.frame, collectionViewLayout: layout)
        view.backgroundColor = PrivateBrowsing.singleton.isOn ? BraveUX.BackgroundColorForTopSitesPrivate : BraveUX.BackgroundColorForBookmarksHistoryAndTopSites
        view.delegate = self

        let thumbnailIdentifier = "Thumbnail"
        view.register(ThumbnailCell.self, forCellWithReuseIdentifier: thumbnailIdentifier)
        view.keyboardDismissMode = .onDrag
        view.alwaysBounceVertical = true
        view.accessibilityIdentifier = "Top Sites View"
        // Entire site panel, including the stats view insets
        view.contentInset = UIEdgeInsetsMake(TopSitesPanelUX.statsHeight, 0, 0, 0)

        return view
    }()
    fileprivate lazy var dataSource: FavoritesDataSource = { return FavoritesDataSource() }()

    // MARK: - Lazy views
    fileprivate lazy var privateTabMessageContainer: UIView = {
        let view = UIView()
        view.isUserInteractionEnabled = true
        view.isHidden = !PrivateBrowsing.singleton.isOn
        return view
    }()
    
    fileprivate lazy var privateTabGraphic: UIImageView = {
        return UIImageView(image: UIImage(named: "private_glasses"))
    }()

    fileprivate lazy var privateTabTitleLabel: UILabel = {
        let view = UILabel()
        view.lineBreakMode = .byWordWrapping
        view.textAlignment = .center
        view.numberOfLines = 0
        view.font = UIFont.systemFont(ofSize: 18, weight: UIFont.Weight.semibold)
        view.textColor = UIColor(white: 1, alpha: 0.6)
        view.text = Strings.Private_Tab_Title
        return view
    }()

    fileprivate lazy var privateTabInfoLabel: UILabel = {
        let view = UILabel()
        view.lineBreakMode = .byWordWrapping
        view.textAlignment = .center
        view.numberOfLines = 0
        view.font = UIFont.systemFont(ofSize: 14, weight: UIFont.Weight.medium)
        view.textColor = UIColor(white: 1, alpha: 1.0)
        view.text = Strings.Private_Tab_Body
        return view
    }()

    fileprivate lazy var privateTabLinkButton: UIButton = {
        let view = UIButton()
        let linkButtonTitle = NSAttributedString(string: Strings.Private_Tab_Link, attributes:
            [NSAttributedStringKey.underlineStyle: NSUnderlineStyle.styleSingle.rawValue])
        view.setAttributedTitle(linkButtonTitle, for: .normal)
        view.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: UIFont.Weight.medium)
        view.titleLabel?.textColor = UIColor(white: 1, alpha: 0.25)
        view.titleLabel?.textAlignment = .center
        view.titleLabel?.lineBreakMode = .byWordWrapping
        view.addTarget(self, action: #selector(showPrivateTabInfo), for: .touchUpInside)
        return view
    }()
    
    fileprivate var ddgLogo = UIImageView(image: UIImage(named: "duckduckgo"))
    
    fileprivate lazy var ddgLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.textColor = BraveUX.GreyD
        label.font = UIFont.systemFont(ofSize: 14, weight: UIFont.Weight.regular)
        label.text = Strings.DDG_promotion
        return label
    }()
    
    fileprivate lazy var ddgButton: UIControl = {
        let control = UIControl()
        control.addTarget(self, action: #selector(showDDGCallout), for: .touchUpInside)
        return control
    }()

    fileprivate lazy var braveShieldStatsView: BraveShieldStatsView = {
        let view = BraveShieldStatsView(frame: CGRect.zero)
        view.autoresizingMask = [.flexibleWidth]
        return view
    }()
    
    /// Called after user taps on ddg popup to set it as a default search enginge in private browsing mode.
    var ddgPrivateSearchCompletionBlock: (() -> ())?

    // MARK: - Init/lifecycle
    init() {
        super.init(nibName: nil, bundle: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(existingUserTopSitesConversion), name: NotificationTopSitesConversion, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(TopSitesPanel.privateBrowsingModeChanged), name: NotificationPrivacyModeChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(TopSitesPanel.updateIphoneConstraints), name: NSNotification.Name.UIDeviceOrientationDidChange, object: nil)
    }

    @objc func existingUserTopSitesConversion() {
        dataSource.refetch()
        collection.reloadData()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: NotificationTopSitesConversion, object: nil)
        NotificationCenter.default.removeObserver(self, name: NotificationPrivacyModeChanged, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.UIDeviceOrientationDidChange, object: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = PrivateBrowsing.singleton.isOn ? BraveUX.BackgroundColorForTopSitesPrivate : BraveUX.BackgroundColorForBookmarksHistoryAndTopSites

        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongGesture(gesture:)))
        collection.addGestureRecognizer(longPressGesture)

        view.addSubview(collection)
        collection.dataSource = PrivateBrowsing.singleton.isOn ? nil : dataSource
        self.dataSource.collectionView = self.collection

        // Could setup as section header but would need to use flow layout,
        // Auto-layout subview within collection doesn't work properly,
        // Quick-and-dirty layout here.
        var statsViewFrame: CGRect = braveShieldStatsView.frame
        statsViewFrame.origin.x = 20
        // Offset the stats view from the inset set above
        statsViewFrame.origin.y = -(TopSitesPanelUX.statsHeight + TopSitesPanelUX.statsBottomMargin)
        statsViewFrame.size.width = collection.frame.width - statsViewFrame.minX * 2
        statsViewFrame.size.height = TopSitesPanelUX.statsHeight
        braveShieldStatsView.frame = statsViewFrame

        collection.addSubview(braveShieldStatsView)
        
        ddgButton.addSubview(ddgLogo)
        ddgButton.addSubview(ddgLabel)

        privateTabMessageContainer.addSubview(privateTabGraphic)
        privateTabMessageContainer.addSubview(privateTabTitleLabel)
        privateTabMessageContainer.addSubview(privateTabInfoLabel)
        privateTabMessageContainer.addSubview(privateTabLinkButton)
        privateTabMessageContainer.addSubview(ddgButton)
        collection.addSubview(privateTabMessageContainer)

        makeConstraints()
        
        if !getApp().browserViewController.shouldShowDDGPromo {
            hideDDG()
        }
        
        if let profile = getApp().profile, profile.searchEngines.defaultEngine(forType: .privateMode).shortName == OpenSearchEngine.EngineNames.duckDuckGo {
            hideDDG()
        }
        
        ddgPrivateSearchCompletionBlock = { [weak self] in
            self?.hideDDG()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // This makes collection view layout to recalculate its cell size.
        collection.collectionViewLayout.invalidateLayout()
    }
    
    func hideDDG() {
        ddgButton.isHidden = true
    }

    /// Handles long press gesture for UICollectionView cells reorder.
    @objc func handleLongGesture(gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            guard let selectedIndexPath = collection.indexPathForItem(at: gesture.location(in: collection)) else {
                break
            }

            dataSource.isEditing = true
            collection.beginInteractiveMovementForItem(at: selectedIndexPath)
        case .changed:
            collection.updateInteractiveMovementTargetPosition(gesture.location(in: gesture.view!))
        case .ended:
            // Allows user to tap anywhere to dimiss 'edit thumbnail' button.
            (view.window as! BraveMainWindow).addTouchFilter(self)
            collection.endInteractiveMovement()
        default:
            collection.cancelInteractiveMovement()
        }
    }

    // MARK: - Constraints setup
    fileprivate func makeConstraints() {
        collection.snp.makeConstraints { make -> Void in
            if #available(iOS 11.0, *) {
                make.edges.equalTo(self.view.safeAreaLayoutGuide.snp.edges)
            } else {
                make.edges.equalTo(self.view)
            }
        }

        privateTabMessageContainer.snp.makeConstraints { (make) -> Void in
            make.centerX.equalTo(collection)
            if UIDevice.current.userInterfaceIdiom == .pad {
                make.centerY.equalTo(self.view)
                make.width.equalTo(400)
            }
            else {
                make.top.equalTo(self.braveShieldStatsView.snp.bottom).offset(25)
                make.leftMargin.equalTo(collection).offset(8)
                make.rightMargin.equalTo(collection).offset(-8)
            }
            make.bottom.equalTo(collection)
        }
        
        privateTabGraphic.snp.makeConstraints { make in
            make.top.equalTo(0)
            make.centerX.equalTo(self.privateTabMessageContainer)
        }

        if UIDevice.current.userInterfaceIdiom == .pad {
            privateTabTitleLabel.snp.makeConstraints { make in
                make.top.equalTo(self.privateTabGraphic.snp.bottom).offset(15)
                make.centerX.equalTo(self.privateTabMessageContainer)
                make.left.right.equalTo(0)
            }

            privateTabInfoLabel.snp.makeConstraints { (make) -> Void in
                make.top.equalTo(self.privateTabTitleLabel.snp.bottom).offset(10)
                if UIDevice.current.userInterfaceIdiom == .pad {
                    make.centerX.equalTo(collection)
                }

                make.left.equalTo(16)
                make.right.equalTo(-16)
            }

            privateTabLinkButton.snp.makeConstraints { (make) -> Void in
                make.top.equalTo(self.privateTabInfoLabel.snp.bottom).offset(10)
                make.left.equalTo(0)
                make.right.equalTo(0)
            }
            
            ddgLogo.snp.makeConstraints { make in
                make.top.left.bottom.equalTo(0)
                make.size.equalTo(38)
            }
            
            ddgLabel.snp.makeConstraints { make in
                make.top.right.bottom.equalTo(0)
                make.left.equalTo(self.ddgLogo.snp.right).offset(5)
                make.width.equalTo(180)
                make.centerY.equalTo(self.ddgLogo)
            }
            
            ddgButton.snp.makeConstraints { make in
                make.top.equalTo(self.privateTabLinkButton.snp.bottom).offset(30)
                make.centerX.equalTo(self.collection)
                make.bottom.equalTo(-8)
            }
        } else {
            updateIphoneConstraints()
        }
    }
    
    override func viewSafeAreaInsetsDidChange() {
        // Not sure why but when a side panel is opened and you transition from portait to landscape
        // top site cells are misaligned, this is a workaroud for this edge case. Happens only on iPhoneX*.
        if #available(iOS 11.0, *) {
            collection.snp.remakeConstraints { make -> Void in
                make.top.equalTo(self.view.safeAreaLayoutGuide.snp.top)
                make.bottom.equalTo(self.view.safeAreaLayoutGuide.snp.bottom)
                make.leading.equalTo(self.view.safeAreaLayoutGuide.snp.leading)
                make.trailing.equalTo(self.view.safeAreaLayoutGuide.snp.trailing).offset(self.view.safeAreaInsets.right)
            }
        }
    }
    
    @objc func updateIphoneConstraints() {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return
        }
        
        let isLandscape = UIApplication.shared.statusBarOrientation.isLandscape
        
        UIView.animate(withDuration: 0.2, animations: {
            self.privateTabGraphic.alpha = isLandscape ? 0 : 1
        })
        
        let offset = isLandscape ? 10 : 15
        
        privateTabTitleLabel.snp.remakeConstraints { make in
            if isLandscape {
                make.top.equalTo(0)
            } else {
                make.top.equalTo(self.privateTabGraphic.snp.bottom).offset(offset)
            }
            make.centerX.equalTo(self.privateTabMessageContainer)
            make.left.right.equalTo(0)
        }
        
        privateTabInfoLabel.snp.remakeConstraints { make in
            make.top.equalTo(self.privateTabTitleLabel.snp.bottom).offset(offset)
            make.left.equalTo(32)
            make.right.equalTo(-32)
        }
        
        privateTabLinkButton.snp.remakeConstraints { make in
            make.top.equalTo(self.privateTabInfoLabel.snp.bottom).offset(offset)
            make.left.equalTo(32)
            make.right.equalTo(-32)
        }
        
        ddgLogo.snp.remakeConstraints { make in
            make.top.left.bottom.equalTo(0)
            make.size.equalTo(38)
        }

        ddgLabel.snp.remakeConstraints { make in
            make.top.right.bottom.equalTo(0)
            make.left.equalTo(self.ddgLogo.snp.right).offset(5)
            make.width.equalTo(180)
            make.centerY.equalTo(self.ddgLogo)
        }
        
        ddgButton.snp.remakeConstraints { make in
            make.top.equalTo(self.privateTabLinkButton.snp.bottom).offset(30)
            make.centerX.equalTo(self.collection)
            make.bottom.equalTo(-8)
        }
        
        self.view.setNeedsUpdateConstraints()
    }

    @objc func showDDGCallout() {
        getApp().browserViewController.presentDDGCallout(force: true)
    }

    func endEditing() {
        guard let window = view.window as? BraveMainWindow else { return }
        window.removeTouchFilter(self)
        dataSource.isEditing = false
    }

    // MARK: - Private browsing modde
    @objc func privateBrowsingModeChanged() {
        let isPrivateBrowsing = PrivateBrowsing.singleton.isOn
        
        if isPrivateBrowsing {
            let profile = getApp().profile
            
            let isDDGSet = profile?.searchEngines.defaultEngine(forType: .privateMode).shortName == OpenSearchEngine.EngineNames.duckDuckGo
            let shouldShowDDGPromo = getApp().browserViewController.shouldShowDDGPromo
            
            ddgButton.isHidden = isDDGSet || !shouldShowDDGPromo
        }

        // TODO: This entire blockshould be abstracted
        //  to make code in this class DRY (duplicates from elsewhere)
        collection.backgroundColor = isPrivateBrowsing ? BraveUX.BackgroundColorForTopSitesPrivate : BraveUX.BackgroundColorForBookmarksHistoryAndTopSites
        privateTabMessageContainer.isHidden = !isPrivateBrowsing
        braveShieldStatsView.timeStatView.color = isPrivateBrowsing ? BraveUX.GreyA : BraveUX.GreyJ
        // Handling edge case when app starts in private only browsing mode and is switched back to normal mode.
        if collection.dataSource == nil && !isPrivateBrowsing {
            collection.dataSource = dataSource
        } else if isPrivateBrowsing {
            collection.dataSource = nil
        }
        collection.reloadData()
    }
    
    @objc     func showPrivateTabInfo() {
        let url = URL(string: "https://github.com/brave/browser-laptop/wiki/What-a-Private-Tab-actually-does")!
        postAsyncToMain {
            let t = getApp().tabManager
            _ = t?.addTabAndSelect(URLRequest(url: url))
        }
    }
}

// MARK: - Delegates
extension TopSitesPanel: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let fav = dataSource.favoriteBookmark(at: indexPath)

        guard let urlString = fav?.url, let url = URL(string: urlString) else { return }

        homePanelDelegate?.homePanel(self, didSelectURL: url)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = collection.frame.width
        let padding: CGFloat = traitCollection.horizontalSizeClass == .compact ? 6 : 20

        let cellWidth = floor(width - padding) / CGFloat(columnsPerRow)
        // The tile's height is determined the aspect ratio of the thumbnails width. We also take into account
        // some padding between the title and the image.
        let cellHeight = floor(cellWidth / (CGFloat(ThumbnailCellUX.ImageAspectRatio) - 0.1))

        return CGSize(width: cellWidth, height: cellHeight)
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let thumbnailCell = cell as? ThumbnailCell else { return }
        thumbnailCell.delegate = self
    }

    fileprivate var columnsPerRow: Int {
        let size = collection.bounds.size
        let traitCollection = collection.traitCollection
        var cols = 0
        if traitCollection.horizontalSizeClass == .compact {
            // Landscape iPhone
            if traitCollection.verticalSizeClass == .compact {
                cols = 5
            }
                // Split screen iPad width
            else if size.widthLargerOrEqualThanHalfIPad() {
                cols = 4
            }
                // iPhone portrait
            else {
                cols = 3
            }
        } else {
            // Portrait iPad
            if size.height > size.width {
                cols = 4;
            }
                // Landscape iPad
            else {
                cols = 5;
            }
        }
        return cols + 1
    }
}

extension TopSitesPanel : WindowTouchFilter {
    func filterTouch(_ touch: UITouch) -> Bool {
        // Allows user to tap anywhere to dimiss 'edit thumbnail' button.
        if (touch.view as? UIButton) == nil && touch.phase == .began {
            self.endEditing()
        }
        return false
    }
}

extension TopSitesPanel: ThumbnailCellDelegate {
    func editThumbnail(_ thumbnailCell: ThumbnailCell) {
        guard let indexPath = collection.indexPath(for: thumbnailCell),
            let fav = dataSource.frc?.fetchedObjects?[indexPath.item] as? Bookmark else { return }

        let actionSheet = UIAlertController(title: fav.displayTitle, message: nil, preferredStyle: .actionSheet)

        let deleteAction = UIAlertAction(title: Strings.Remove_Favorite, style: .destructive) { _ in
            fav.remove(save: true)
            
            // Remove cached icon.
            if let urlString = fav.url, let url = URL(string: urlString) {
                ImageCache.shared.remove(url, type: .square)
            }
            
            self.dataSource.isEditing = false
        }

        let editAction = UIAlertAction(title: Strings.Edit_Favorite, style: .default) { _ in
            guard let title = fav.displayTitle, let urlString = fav.url else { return }

            let editPopup = UIAlertController.userTextInputAlert(title: Strings.Edit_Bookmark, message: urlString,
                                                             startingText: title, startingText2: fav.url,
                                                             placeholder2: urlString,
                                                             keyboardType2: .URL) { callbackTitle, callbackUrl in
                if let cTitle = callbackTitle, !cTitle.isEmpty, let cUrl = callbackUrl, !cUrl.isEmpty {
                    if URL(string: cUrl) != nil {
                        fav.update(customTitle: cTitle, url: cUrl, save: true)
                    }
                }
                self.dataSource.isEditing = false
            }

            self.present(editPopup, animated: true, completion: nil)
        }

        let cancelAction = UIAlertAction(title: Strings.Cancel, style: .cancel, handler: nil)

        actionSheet.addAction(editAction)
        actionSheet.addAction(deleteAction)
        actionSheet.addAction(cancelAction)
        
        if DeviceDetector.isIpad {
            actionSheet.popoverPresentationController?.permittedArrowDirections = .any
            actionSheet.popoverPresentationController?.sourceView = thumbnailCell
            actionSheet.popoverPresentationController?.sourceRect = thumbnailCell.bounds
            present(actionSheet, animated: true, completion: nil)
        } else {
            present(actionSheet, animated: true) {
                self.dataSource.isEditing = false
            }
        }
    }
}

extension CGSize {
    public func widthLargerOrEqualThanHalfIPad() -> Bool {
        let halfIPadSize: CGFloat = 507
        return width >= halfIPadSize
    }
}
