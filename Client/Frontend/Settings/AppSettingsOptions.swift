/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared

import SwiftKeychainWrapper
import LocalAuthentication

// This file contains all of the settings available in the main settings screen of the app.

private var ShowDebugSettings: Bool = false
private var DebugSettingsClickCount: Int = 0

// For great debugging!
class HiddenSetting: Setting {
    let settings: SettingsTableViewController

    init(settings: SettingsTableViewController) {
        self.settings = settings
        super.init(title: nil)
    }

    override var hidden: Bool {
        return !ShowDebugSettings
    }
}


class DeleteExportedDataSetting: HiddenSetting {
    override var title: NSAttributedString? {
        // Not localized for now.
        return NSAttributedString(string: "Debug: delete exported databases", attributes: [NSAttributedStringKey.foregroundColor: UIConstants.TableViewRowTextColor])
    }

    override func onClick(_ navigationController: UINavigationController?) {
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let fileManager = FileManager.default
        do {
            let files = try fileManager.contentsOfDirectory(atPath: documentsPath)
            for file in files {
                if file.startsWith("browser.") || file.startsWith("logins.") {
                    try fileManager.removeItemInDirectory(documentsPath, named: file)
                }
            }
        } catch {
            print("Couldn't delete exported data: \(error).")
        }
    }
}

class ExportBrowserDataSetting: HiddenSetting {
    override var title: NSAttributedString? {
        // Not localized for now.
        return NSAttributedString(string: "Debug: copy databases to app container", attributes: [NSAttributedStringKey.foregroundColor: UIConstants.TableViewRowTextColor])
    }

    override func onClick(_ navigationController: UINavigationController?) {
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        do {
            let log = Logger.syncLogger
            try self.settings.profile.files.copyMatching(fromRelativeDirectory: "", toAbsoluteDirectory: documentsPath) { file in
                log.debug("Matcher: \(file)")
                return file.startsWith("browser.") || file.startsWith("logins.")
            }
        } catch {
            print("Couldn't export browser data: \(error).")
        }
    }
}

// Opens the the license page in a new tab
class LicenseAndAcknowledgementsSetting: Setting {
    override var url: URL? {
        return URL(string: WebServer.sharedInstance.URLForResource("license", module: "about"))
    }

    override func onClick(_ navigationController: UINavigationController?) {
        setUpAndPushSettingsContentViewController(navigationController)
    }
}

// Opens the on-boarding screen again
class ShowIntroductionSetting: Setting {
    let profile: Profile

    init(settings: SettingsTableViewController) {
        self.profile = settings.profile
        super.init(title: NSAttributedString(string: Strings.ShowTour, attributes: [NSAttributedStringKey.foregroundColor: UIConstants.TableViewRowTextColor]))
    }

    override func onClick(_ navigationController: UINavigationController?) {
        navigationController?.dismiss(animated: true, completion: {
            if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
                appDelegate.browserViewController.presentIntroViewController(true)
            }
        })
    }
}

// Opens the search settings pane
class SearchSetting: Setting {
    let profile: Profile

    override var accessoryType: UITableViewCellAccessoryType { return .disclosureIndicator }

    override var style: UITableViewCellStyle { return .value1 }

    override var accessibilityIdentifier: String? { return "Search" }

    init(settings: SettingsTableViewController) {
        self.profile = settings.profile
        super.init(title: NSAttributedString(string: Strings.DefaultSearchEngine, attributes: [NSAttributedStringKey.foregroundColor: UIConstants.TableViewRowTextColor]))
    }

    override func onClick(_ navigationController: UINavigationController?) {
        let viewController = SearchSettingsTableViewController()
        viewController.model = profile.searchEngines
        navigationController?.pushViewController(viewController, animated: true)
    }
}

class LoginsSetting: Setting {
    let profile: Profile
    weak var navigationController: UINavigationController?

    override var accessoryType: UITableViewCellAccessoryType { return .disclosureIndicator }

    override var accessibilityIdentifier: String? { return "Logins" }

    init(settings: SettingsTableViewController, delegate: SettingsDelegate?) {
        self.profile = settings.profile
        self.navigationController = settings.navigationController

        let loginsTitle = Strings.Logins
        super.init(title: NSAttributedString(string: loginsTitle, attributes: [NSAttributedStringKey.foregroundColor: UIConstants.TableViewRowTextColor]),
                   delegate: delegate)
    }

    fileprivate func navigateToLoginsList() {
        let viewController = LoginListViewController(profile: profile)
        viewController.settingsDelegate = delegate
        navigationController?.pushViewController(viewController, animated: true)
    }
}

class SyncDevicesSetting: Setting {
    let profile: Profile
    
    override var accessoryType: UITableViewCellAccessoryType { return .disclosureIndicator }
    
    override var accessibilityIdentifier: String? { return "Sync" }
    
    init(settings: SettingsTableViewController) {
        self.profile = settings.profile
        
        let clearTitle = Strings.Sync
        super.init(title: NSAttributedString(string: clearTitle, attributes: [NSAttributedStringKey.foregroundColor: UIConstants.TableViewRowTextColor]))
    }
    
    override func onClick(_ navigationController: UINavigationController?) {
        
        if Sync.shared.isInSyncGroup {
            let syncSettingsView = SyncSettingsViewController(style: .grouped)
            syncSettingsView.profile = getApp().profile
            navigationController?.pushViewController(syncSettingsView, animated: true)
        } else {
            let view = SyncWelcomeViewController()
            navigationController?.pushViewController(view, animated: true)
        }
    }
}

class SyncDeviceSetting: Setting {
    let profile: Profile
    
    var onTap: (()->Void)?
    internal var device: Device
    
    internal var displayTitle: String {
        return device.name ?? ""
    }
    
    override var accessoryType: UITableViewCellAccessoryType { return .none }
    
    override var accessibilityIdentifier: String? { return "SyncDevice" }
    
    init(profile: Profile, device: Device) {
        self.profile = profile
        self.device = device
        super.init(title: NSAttributedString(string: device.name ?? "", attributes: [NSAttributedStringKey.foregroundColor: UIConstants.TableViewRowTextColor]))
    }
    
    override func onClick(_ navigationController: UINavigationController?) {
        onTap?()
    }
}

class ClearPrivateDataSetting: Setting {
    let profile: Profile

    override var accessoryType: UITableViewCellAccessoryType { return .disclosureIndicator }

    override var accessibilityIdentifier: String? { return "ClearPrivateData" }

    init(settings: SettingsTableViewController) {
        self.profile = settings.profile

        let clearTitle = Strings.ClearPrivateData
        super.init(title: NSAttributedString(string: clearTitle, attributes: [NSAttributedStringKey.foregroundColor: UIConstants.TableViewRowTextColor]))
    }

    override func onClick(_ navigationController: UINavigationController?) {
        let viewController = ClearPrivateDataTableViewController()
        viewController.profile = profile
        navigationController?.pushViewController(viewController, animated: true)
    }
}

class PrivacyPolicySetting: Setting {
    override var title: NSAttributedString? {
        return NSAttributedString(string: Strings.Privacy_Policy, attributes: [NSAttributedStringKey.foregroundColor: UIConstants.TableViewRowTextColor])
    }

    override var url: URL? {
        return URL(string: "https://www.brave.com/ios_privacy.html")
    }

    override func onClick(_ navigationController: UINavigationController?) {
        setUpAndPushSettingsContentViewController(navigationController)
    }
}

class ChangePinSetting: Setting {
    let profile: Profile
    
    override var accessoryType: UITableViewCellAccessoryType { return .disclosureIndicator }
    
    override var accessibilityIdentifier: String? { return "ChangePin" }
    
    init(settings: SettingsTableViewController) {
        self.profile = settings.profile
        
        let clearTitle = Strings.Change_Pin
        super.init(title: NSAttributedString(string: clearTitle, attributes: [NSAttributedStringKey.foregroundColor: UIConstants.TableViewRowTextColor]))
    }
    
    override func onClick(_ navigationController: UINavigationController?) {
        if profile.prefs.boolForKey(kPrefKeyBrowserLock) == true {
            getApp().requirePinIfNeeded(profile: profile)
            getApp().securityViewController?.auth()
        }
        
        let view = PinViewController()
        navigationController?.pushViewController(view, animated: true)
    }
}
