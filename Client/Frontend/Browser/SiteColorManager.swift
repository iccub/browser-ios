/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import WebKit
import Storage
import WebImage


class SiteColorManager: BrowserHelper {
    let profile: Profile
    weak var browser: Browser?
    
    init(browser: Browser, profile: Profile) {
        self.profile = profile
        self.browser = browser
        
        if let path = Bundle.main.path(forResource: "ThemeColor", ofType: "js") {
            if let source = try? NSString(contentsOfFile: path, encoding: String.Encoding.utf8.rawValue) as String {
                let userScript = WKUserScript(source: source, injectionTime: WKUserScriptInjectionTime.atDocumentEnd, forMainFrameOnly: true)
                browser.webView!.configuration.userContentController.addUserScript(userScript)
            }
        }
    }
    
    class func scriptMessageHandlerName() -> String? {
        return "siteColorMessageHandler"
    }
    
    func userContentController(_ userContentController: WKUserContentController, didReceiveScriptMessage message: WKScriptMessage) {
        guard let tab = browser else { return }
        guard let data = message.body as? [String: String], let themeColor = data["themeColor"] else { return }
        
        // Convert rgb(#, #, #) or hex color to UIColor
        var color: UIColor? = nil
        if themeColor.contains("#") {
            let hex = themeColor.replacingOccurrences(of: "#", with: "")
            color = UIColor(colorString: hex)
        } else {
            let rgbRaw: [Substring] = themeColor.split(separator: "(")[1].split(separator: ")")[0].split(separator: " ").joined(separator: "").split(separator: ",")
            let rgb: [Int] = rgbRaw.map { Int(String($0)) ?? 255 }
            color = UIColor(red: CGFloat(rgb[0])/255.0, green: CGFloat(rgb[1])/255.0, blue: CGFloat(rgb[2])/255.0, alpha: 1)
        }
        if let color = color {
            tab.color = color
        }
    }
}
