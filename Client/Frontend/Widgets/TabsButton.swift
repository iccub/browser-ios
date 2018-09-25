/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import SnapKit
import Shared
import XCGLogger

private let log = Logger.browserLogger

struct TabsButtonUX {
    static let CornerRadius: CGFloat = 2
    static let TitleFont: UIFont = UIFont.systemFont(ofSize: 10, weight: UIFont.Weight.semibold)
    static let BorderStrokeWidth: CGFloat = 1.5
    static let BorderColor = UIColor.clear
    static let HighlightButtonColor = UIColor.clear
    static let TitleInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

    static let Themes: [String: Theme] = {
        var themes = [String: Theme]()
        var theme = Theme()
        theme.borderColor = BraveUX.GreyG
        theme.borderWidth = BorderStrokeWidth
        theme.font = TitleFont
        theme.backgroundColor = .clear
        theme.textColor = BraveUX.GreyG
        theme.insets = TitleInsets
        theme.highlightButtonColor = BraveUX.GreyA
        theme.highlightTextColor = BraveUX.GreyA
        theme.highlightBorderColor = BraveUX.GreyA
        themes[Theme.PrivateMode] = theme

        theme = Theme()
        theme.borderColor = BraveUX.GreyI
        theme.borderWidth = BorderStrokeWidth
        theme.font = TitleFont
        theme.backgroundColor = .clear
        theme.textColor = BraveUX.GreyI
        theme.insets = TitleInsets
        theme.highlightButtonColor = BraveUX.GreyJ
        theme.highlightTextColor = BraveUX.GreyJ
        theme.highlightBorderColor = BraveUX.GreyJ
        themes[Theme.NormalMode] = theme

        return themes
    }()
}

class TabsButton: UIControl {
    fileprivate var theme: Theme = TabsButtonUX.Themes[Theme.NormalMode]!
    
    fileprivate var imageView: UIImageView = UIImageView(image: UIImage(named: "tabs")?.withRenderingMode(.alwaysTemplate))
    
    override var isHighlighted: Bool {
        didSet {
            if isHighlighted {
                borderColor = theme.highlightBorderColor!
                titleBackgroundColor = theme.highlightButtonColor
                textColor = theme.highlightTextColor
            } else {
                borderColor = theme.borderColor!
                titleBackgroundColor = theme.backgroundColor
                textColor = theme.textColor
            }
        }
    }

    lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = NSTextAlignment.center
        label.isUserInteractionEnabled = false
        return label
    }()

    lazy var insideButton: UIView = {
        let view = UIView()
        view.clipsToBounds = false
        view.isUserInteractionEnabled = false
        return view
    }()

    lazy var labelBackground: UIView = {
        let background = UIView()
        background.layer.cornerRadius = TabsButtonUX.CornerRadius
        background.isUserInteractionEnabled = false
        return background
    }()

    lazy var borderView: InnerStrokedView = {
        let border = InnerStrokedView()
        border.strokeWidth = TabsButtonUX.BorderStrokeWidth
        border.cornerRadius = TabsButtonUX.CornerRadius
        border.isUserInteractionEnabled = false
        return border
    }()

    fileprivate var buttonInsets: UIEdgeInsets = TabsButtonUX.TitleInsets

    override init(frame: CGRect) {
        super.init(frame: frame)
        
//        insideButton.addSubview(imageView)
        insideButton.addSubview(labelBackground)
        insideButton.addSubview(borderView)
        insideButton.addSubview(titleLabel)
        
        addSubview(insideButton)
        isAccessibilityElement = true
        accessibilityTraits |= UIAccessibilityTraitButton
        
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(tabsButtonHold))
        longPress.minimumPressDuration = 0.2
        addGestureRecognizer(longPress)
    }

    override func updateConstraints() {
        super.updateConstraints()

//            imageView.contentMode = .center
//            imageView.snp.remakeConstraints { (make) -> Void in
//                make.edges.equalTo(insideButton)
//            }

        labelBackground.snp.remakeConstraints { (make) -> Void in
            make.edges.equalTo(insideButton)
        }
        borderView.snp.remakeConstraints { (make) -> Void in
            make.edges.equalTo(insideButton)
        }
        titleLabel.snp.remakeConstraints { (make) -> Void in
            make.edges.equalTo(insideButton)
        }
        
        insideButton.snp.remakeConstraints { (make) -> Void in
          // BRAVE mod: getting layout errors with firefox method, temporary hack to bypass the errors
          make.right.equalTo(self).inset(12)
          make.centerY.equalTo(self)
          make.size.equalTo(19)
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc func tabsButtonHold() {
        let actionSheetController = UIAlertController(title: nil, message: nil, preferredStyle: UIAlertControllerStyle.actionSheet)
        let closeAllTitle = String(format: Strings.CloseAllTabsTitle, getApp().tabManager.tabs.displayedTabsForCurrentPrivateMode.count)
        let closeAllTabsAction =  UIAlertAction(title: closeAllTitle, style: UIAlertActionStyle.destructive) { (action: UIAlertAction) in
            getApp().tabManager.removeAll(createTabIfNoneLeft: true, restricted: true)
        }
        
        let closeTabAction =  UIAlertAction(title: Strings.CloseTabTitle, style: UIAlertActionStyle.destructive) { (action: UIAlertAction) in
            if let tab = getApp().tabManager.selectedTab {
                getApp().tabManager.removeTab(tab, createTabIfNoneLeft: true)
            }
        }
        
        let cancelAction = UIAlertAction(title: Strings.Cancel, style: UIAlertActionStyle.cancel, handler: nil)
        actionSheetController.addAction(cancelAction)
        
        if UIDevice.current.userInterfaceIdiom == .pad {
            if !PrivateBrowsing.singleton.isOn {
                let newPrivateTabAction = UIAlertAction(title: Strings.NewPrivateTabTitle,
                                                        style: .default,
                                                        handler: respondToNewPrivateTab(action:))
                actionSheetController.addAction(newPrivateTabAction)
            }
            
            let newTabAction = UIAlertAction(title: Strings.NewTabTitle,
                                             style: .default,
                                             handler: respondToNewTab(action:))
            actionSheetController.addAction(newTabAction)
            
            if let presenter = actionSheetController.popoverPresentationController {
                presenter.sourceView = self
                presenter.sourceRect = self.bounds
            }
        }
        actionSheetController.addAction(closeAllTabsAction)
        actionSheetController.addAction(closeTabAction)
        
        getApp().browserViewController.present(actionSheetController, animated: true, completion: nil)
    }
}

extension TabsButton: Themeable {
    func applyTheme(_ themeName: String) {

        guard let theme = TabsButtonUX.Themes[themeName] else {
            log.error("Unable to apply unknown theme \(themeName)")
            return
        }

        borderColor = theme.borderColor!
        borderWidth = theme.borderWidth!
        titleFont = theme.font
        titleBackgroundColor = theme.backgroundColor
        textColor = theme.textColor
        insets = theme.insets!

        self.theme = theme
    }
}

// MARK: UIAppearance
extension TabsButton {
    
    @objc dynamic var borderColor: UIColor {
        get { return borderView.color }
        set {
            borderView.color = newValue
            imageView.tintColor = newValue
        }
    }

    @objc dynamic var borderWidth: CGFloat {
        get { return borderView.strokeWidth }
        set { borderView.strokeWidth = newValue }
    }

    @objc dynamic var textColor: UIColor? {
        get { return titleLabel.textColor }
        set { titleLabel.textColor = newValue }
    }

    @objc dynamic var titleFont: UIFont? {
        get { return titleLabel.font }
        set { titleLabel.font = newValue }
    }

    @objc dynamic var titleBackgroundColor: UIColor? {
        get { return labelBackground.backgroundColor }
        set { labelBackground.backgroundColor = newValue }
    }

    @objc dynamic var insets : UIEdgeInsets {
        get { return buttonInsets }
        set {
            buttonInsets = newValue
            setNeedsUpdateConstraints()
        }
    }
}

// MARK: - BraveBrowserToolbarButtonActions Conformance
extension TabsButton: BraveBrowserToolbarButtonActions {}
