/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared

class AdblockNetworkDataFileLoader: NetworkDataFileLoader {
    var lang = AdBlocker.defaultLocale
}

typealias localeCode = String

private let log = Logger.browserLogger

class AdBlocker {
    static let singleton = AdBlocker()

    static let prefKey = "braveBlockAdsAndTracking"
    static let prefKeyDefaultValue = true
    static let prefKeyUseRegional = "braveAdblockUseRegional"
    static let prefKeyUseRegionalDefaultValue = true
    static let dataVersion: Int32 = 4
    
    static let dataVersionPrefKey = "dataVersionPrefKey"
    static let defaultLocale = "en"

    let adBlockDataFolderName = "abp-data"
    let adBlockRegionFilePath = Bundle.main.path(forResource: "adblock-regions", ofType: "txt")
    let adBlockDataUrlPath = "https://adblock-data.s3.brave.com/"
    
    var isNSPrefEnabled = true
    fileprivate var fifoCacheOfUrlsChecked = FifoDict()
    fileprivate var regionToS3FileName = [localeCode: String]()
    fileprivate var networkLoaders = [localeCode: AdblockNetworkDataFileLoader]()
    fileprivate lazy var abpFilterLibWrappers: [localeCode: ABPFilterLibWrapper] = { 
        return [AdBlocker.defaultLocale : ABPFilterLibWrapper()] 
    }()
    var currentLocaleCode: localeCode = defaultLocale {
        didSet {
            updateRegionalAdblockEnabledState()
        }
    }
    fileprivate var isRegionalAdblockEnabled = prefKeyUseRegionalDefaultValue

    fileprivate init() {
        setDataVersionPreference()
        updateEnabledState()
        networkLoaders[AdBlocker.defaultLocale] = getNetworkLoader(forLocale: AdBlocker.defaultLocale, name: "ABPFilterParserData")
        parseAdblockRegionsFile()
        
        // so that didSet is called from init
        defer { currentLocaleCode = Locale.current.languageCode ?? AdBlocker.defaultLocale }
    }
    
    private func parseAdblockRegionsFile() {
        guard let filePath = adBlockRegionFilePath, 
            let regional = try? String(contentsOfFile: filePath, encoding: String.Encoding.utf8) else {
            log.error("Could not find adblock regions file")
            return
        }
        
        regional.components(separatedBy: "\n").forEach {
            let parts = $0.components(separatedBy: ",")
            guard let filename = parts.last, parts.count > 1 else {
                return
            }
            
            for (_, locale) in parts.enumerated() {
                if regionToS3FileName[locale] != nil { log.info("Duplicate regions not handled yet \(locale)") }
                
                if locale.count > 2 {
                    log.info("Only 2 letter locale codes are handled.")
                    let firstTwoLocaleCharacters = locale.substring(to: locale.index(locale.startIndex, offsetBy: 2))
                    regionToS3FileName[firstTwoLocaleCharacters] = filename
                } else { 
                    regionToS3FileName[locale] = filename
                }
            }
        }
    }
    
    /// We want to avoid situations in which user still has downloaded old abp data version.
    /// We remove all abp data after data version is updated, then the newest data is downloaded. 
    private func setDataVersionPreference() {
        guard let prefs = BraveApp.getPrefs() else {
            log.error("No prefs found")
            return
        }
        guard let dataVersionPref = prefs.intForKey(AdBlocker.dataVersionPrefKey), dataVersionPref == AdBlocker.dataVersion else { 
            cleanDatFiles()
            prefs.setInt(AdBlocker.dataVersion, forKey: AdBlocker.dataVersionPrefKey)

            return
        }
    }
    
    private func cleanDatFiles() {
        guard let dir = NetworkDataFileLoader.directoryPath else { return }
        
        let fm = FileManager.default
        do {
            let folderPath = dir + "/\(adBlockDataFolderName)"
            let paths = try fm.contentsOfDirectory(atPath: folderPath)
            for path in paths {
                try fm.removeItem(atPath: "\(folderPath)/\(path)")
            }
        } catch {
            log.error(error.localizedDescription)
        }
    }

    fileprivate func getNetworkLoader(forLocale locale: localeCode, name: String) -> AdblockNetworkDataFileLoader {
        let dataUrl = URL(string: "\(adBlockDataUrlPath)\(AdBlocker.dataVersion)/\(name).dat")!
        let dataFile = "abp-data-\(AdBlocker.dataVersion)-\(locale).dat"
        let loader = AdblockNetworkDataFileLoader(url: dataUrl, file: dataFile, localDirName: adBlockDataFolderName)
        loader.lang = locale
        loader.delegate = self
        return loader
    }

    func startLoading() {
        networkLoaders.forEach { $0.1.loadData() }
    }

    func isRegionalAdblockPossible() -> (hasRegionalFile: Bool, isDefaultSettingOn: Bool) {
        return (hasRegionalFile: currentLocaleCode != AdBlocker.defaultLocale && regionToS3FileName[currentLocaleCode] != nil,
                isDefaultSettingOn: isRegionalAdblockEnabled)
   }

    func updateEnabledState() {
        isNSPrefEnabled = BraveApp.getPrefs()?.boolForKey(AdBlocker.prefKey) ?? AdBlocker.prefKeyDefaultValue
    }

    fileprivate func updateRegionalAdblockEnabledState() {
        isRegionalAdblockEnabled = BraveApp.getPrefs()?.boolForKey(AdBlocker.prefKeyUseRegional) ?? AdBlocker.prefKeyUseRegionalDefaultValue

        if currentLocaleCode != AdBlocker.defaultLocale && isRegionalAdblockEnabled {
            if let file = regionToS3FileName[currentLocaleCode] {
                if networkLoaders[currentLocaleCode] == nil {
                    networkLoaders[currentLocaleCode] = getNetworkLoader(forLocale: currentLocaleCode, name: file)
                    abpFilterLibWrappers[currentLocaleCode] = ABPFilterLibWrapper()

                }
            } else {
                log.warning("No custom adblock file for \(self.currentLocaleCode)")
            }
        }
    }

    // We can add whitelisting logic here for puzzling adblock problems
    fileprivate func isWhitelistedUrl(_ url: String?, forMainDocDomain domain: String) -> Bool {
        guard let url = url else { return false }
        // https://github.com/brave/browser-ios/issues/89
        if domain.contains("yahoo") && url.contains("s.yimg.com/zz/combo") {
            return true
        }

        // issue 385
        if domain.contains("m.jpost.com") {
            return true
        }

        return false
    }

    func setForbesCookie() {
        let cookieName = "forbes bypass"
        let storage = HTTPCookieStorage.shared
        let existing = storage.cookies(for: URL(string: "http://www.forbes.com")!)
        if let existing = existing {
            for c in existing {
                if c.name == cookieName {
                    return
                }
            }
        }

        var dict: [HTTPCookiePropertyKey:Any] = [:]
        dict[HTTPCookiePropertyKey.path] = "/"
        dict[HTTPCookiePropertyKey.name] = cookieName
        dict[HTTPCookiePropertyKey.value] = "forbes_ab=true; welcomeAd=true; adblock_session=Off; dailyWelcomeCookie=true"
        dict[HTTPCookiePropertyKey.domain] = "www.forbes.com"

        let components: DateComponents = DateComponents()
        (components as NSDateComponents).setValue(1, forComponent: NSCalendar.Unit.month);
        dict[HTTPCookiePropertyKey.expires] = (Calendar.current as NSCalendar).date(byAdding: components, to: Date(), options: NSCalendar.Options(rawValue: 0))

        let newCookie = HTTPCookie(properties: dict)
        if let c = newCookie {
            storage.setCookie(c)
        }
    }

    class RedirectLoopGuard {
        let timeWindow: TimeInterval // seconds
        let maxRedirects: Int
        var startTime = Date()
        var redirects = 0

        init(timeWindow: TimeInterval, maxRedirects: Int) {
            self.timeWindow = timeWindow
            self.maxRedirects = maxRedirects
        }

        func isLooping() -> Bool {
            return redirects > maxRedirects
        }

        func increment() {
            let time = Date()
            if time.timeIntervalSince(startTime) > timeWindow {
                startTime = time
                redirects = 0
            }
            redirects += 1
        }
    }

    // In the valid case, 4-5x we see 'forbes/welcome' page in succession (URLProtocol can call more than once for an URL, this is well documented)
    // Set the window as 10x in 10sec, after that stop forwarding the page.
    var forbesRedirectGuard = RedirectLoopGuard(timeWindow: 10.0, maxRedirects: 10)

    func shouldBlock(_ request: URLRequest) -> Bool {
        // synchronize code from this point on.
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }

        guard let url = request.url else {
            return false
        }
        
        // Do not block main frame urls
        // e.g. user clicked on an ad intentionally (adblock could block redirect to requested site)
        let currentTabUrl = getApp().browserViewController.tabManager.selectedTab?.url
        if url == currentTabUrl { return false }

        if url.host?.contains("forbes.com") ?? false {
            setForbesCookie()

            if url.absoluteString.contains("/forbes/welcome") {
                forbesRedirectGuard.increment()
                if !forbesRedirectGuard.isLooping() {
                    postAsyncToMain(0.5) {
                        /* For some reason, even with the cookie set, I can't get past the welcome page, until I manually load a page on forbes. So if a do a google search for a subpage on forbes, I can click on that and get to forbes, and from that point on, I no longer see the welcome page. This hack seems to work perfectly for duplicating that behaviour. */
                        BraveApp.getCurrentWebView()?.loadRequest(URLRequest(url: URL(string: "http://www.forbes.com")!))
                    }
                }
            }
        }


        if let main = request.mainDocumentURL?.absoluteString, (main.startsWith(WebServer.sharedInstance.base)) {
            if !main.contains("testing/") { // don't skip for localhost testing
                return false
            }
        }

        var mainDocDomain = request.mainDocumentURL?.host ?? ""
        mainDocDomain = stripLocalhostWebServer(mainDocDomain)

        if isWhitelistedUrl(url.absoluteString, forMainDocDomain: mainDocDomain) {
            return false
        }

        // A cache entry is like: fifoOfCachedUrlChunks[0]["www.microsoft.com_http://some.url"] = true/false for blocking
        let key = "\(mainDocDomain)_" + stripLocalhostWebServer(url.absoluteString)

        if let checkedItem = fifoCacheOfUrlsChecked.getItem(key) {
            if checkedItem === NSNull() {
                return false
            } else {
                return checkedItem as! Bool
            }
        }

        var isBlocked = false
        var blockedByLocale = ""
        for (locale, adblocker) in abpFilterLibWrappers {
            isBlocked = adblocker.isBlockedConsideringType(url.absoluteString,
                                                           mainDocumentUrl: mainDocDomain,
                                                           acceptHTTPHeader:request.value(forHTTPHeaderField: "Accept"))

            if isBlocked {
                blockedByLocale = locale
                if locale != AdBlocker.defaultLocale && AppConstants.IsRunningTest {
                    messageUITest(identifier: "blocked-url", message:"\(blockedByLocale) \(url.absoluteString)")
                }
                break
            }
        }
        fifoCacheOfUrlsChecked.addItem(key, value: isBlocked as AnyObject)


        if isBlocked {
            log.debug("blocked \(url.absoluteString)")
        }

        return isBlocked
    }

    // Hack to use a UILabel to send UITest app a message
    fileprivate func messageUITest(identifier:String, message: String) {
        postAsyncToMain {
            let tag = 19283
            let v = getApp().rootViewController.view.viewWithTag(tag) as? UILabel ?? UILabel()
            if v.tag != tag {
                getApp().rootViewController.view.addSubview(v)
                v.tag = tag
                v.frame = CGRect(x: 0, y: 0, width: 200, height: 10)
                v.alpha = 0.1
            }
            v.text = message
            v.accessibilityValue = message
            v.accessibilityLabel = identifier
            v.accessibilityIdentifier = identifier
        }
    }
}

extension AdBlocker: NetworkDataFileLoaderDelegate {

    func fileLoader(_ loader: NetworkDataFileLoader, setDataFile data: Data?) {
        guard let loader = loader as? AdblockNetworkDataFileLoader, let adblocker = abpFilterLibWrappers[loader.lang] else {
            assert(false)
            return
        }
        adblocker.setDataFile(data)
    }

    func fileLoaderHasDataFile(_ loader: NetworkDataFileLoader) -> Bool {
        guard let loader = loader as? AdblockNetworkDataFileLoader, let adblocker = abpFilterLibWrappers[loader.lang] else {
            assert(false)
            return false
        }
        return adblocker.hasDataFile()
    }

    func fileLoaderDelegateWillHandleInitialRead(_ loader: NetworkDataFileLoader) -> Bool {
        return false
    }
}
