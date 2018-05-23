/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

/**
 * Handles the page request to about/home/ so that the page loads and does not throw an error (404) on initialization
 */
import GCDWebServers

struct AboutHomeHandler {
    static func register(_ webServer: WebServer) {
        webServer.registerHandlerForMethod("GET", module: "about", resource: "home") { (request: GCDWebServerRequest!) -> GCDWebServerResponse? in
            return GCDWebServerResponse(statusCode: webServer.isRequestAuthenticated(request) ? 200 : 401)
        }
    }
}

extension GCDWebServerDataResponse {
    convenience init(XHTML: String) {
        let data = XHTML.data(using: String.Encoding.utf8, allowLossyConversion: false)
        self.init(data: data, contentType: "application/xhtml+xml; charset=utf-8")
    }
}
