/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import CoreData
import Shared

var requestCount = 0
let markerRequestHandled = "request-already-handled"

private let log = Logger.browserLogger

/*
 When URLProtocol is called, the WebThread is locked; we need to be wary of deadlock
 if we call other places in the code that may also have locks, because if the URLProtocol
 doesn't return, the WebThread is locked, and accessing UIWebView on the main thread will deadlock.
 */

class URLProtocol: Foundation.URLProtocol {

    var session: URLSession?
    var dataTask: URLSessionDataTask?
    var disableJavascript = false
    static var testShieldState: BraveShieldState?
    
    override init(request: URLRequest, cachedResponse: CachedURLResponse?, client: URLProtocolClient?) {
        super.init(request: request, cachedResponse: cachedResponse, client: client)
        
        if session == nil {
            session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        if UserReferralProgram.shouldAddCustomHeader(for: request) != nil {
            return true
        }

        //print("Request #\(requestCount++): URL = \(request.mainDocumentURL?.absoluteString)")
        if let scheme = request.url?.scheme, !scheme.startsWith("http") {
            return false
        }

        if Foundation.URLProtocol.property(forKey: markerRequestHandled, in: request) != nil {
            return false
        }

        guard let url = request.url else { return false }
        
        // We let reader moded requests through to add auth headers to them.
        if ReaderModeUtils.isReaderModeURL(url) {
            return true
        }

        let shieldState = testShieldState != nil ? testShieldState! : getShields(request)
        if shieldState.isAllOff() {
            return false
        }
        
        let useCustomUrlProtocol =
            shieldState.isOnScriptBlocking() ?? false ||
            (shieldState.isOnAdBlockAndTp() ?? false && TrackingProtection.singleton.shouldBlock(request)) ||
                (shieldState.isOnAdBlockAndTp() ?? false && AdBlocker.singleton.shouldBlock(request)) ||
                (shieldState.isOnSafeBrowsing() ?? false && SafeBrowsing.singleton.shouldBlock(request)) ||
                (shieldState.isOnHTTPSE() ?? false && HttpsEverywhere.singleton.tryRedirectingUrl(url) != nil)

        return useCustomUrlProtocol
    }

    // Tries to use the UA to match to requesting webview.
    // If it fails use current selected webview
    /*
     - request arrives in protocol
     - protocol maps request to brave web view
     - brave web view has shield state, grab that state, apply it to request
     */
    static func getShields(_ request: URLRequest) -> BraveShieldState {
        let ua = request.allHTTPHeaderFields?["User-Agent"]
        var webViewShield:BraveShieldState? = nil
        var shieldResult = BraveShieldState()

        struct LastBrowserTab { static weak var val: Browser? }
        if let browserTab = BrowserTabToUAMapper.userAgentToBrowserTab(ua) {
            LastBrowserTab.val = browserTab
            webViewShield = browserTab.braveShieldStateSafeAsync.get()
        } else {
            // some requests arrive with no user agent, can only assume which tab to use
            webViewShield = LastBrowserTab.val?.braveShieldStateSafeAsync.get()
        }

        if let webViewShield = webViewShield, webViewShield.isAllOff() {
            shieldResult.setState(.AllOff, on: true)
            return shieldResult
        }

        shieldResult.setStateFromPerPageShield(webViewShield)
        
        return shieldResult
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    fileprivate class func cloneRequest(_ request: URLRequest) -> NSMutableURLRequest {
        // Reportedly not safe to use built-in cloning methods: http://openradar.appspot.com/11596316
        let newRequest = NSMutableURLRequest(url: request.url!, cachePolicy: request.cachePolicy, timeoutInterval: request.timeoutInterval)
        newRequest.allHTTPHeaderFields = request.allHTTPHeaderFields
        if let m = request.httpMethod {
            newRequest.httpMethod = m
        }
        if let b = request.httpBodyStream {
            newRequest.httpBodyStream = b
        }
        if let b = request.httpBody {
            newRequest.httpBody = b
        }
        newRequest.httpShouldUsePipelining = request.httpShouldUsePipelining
        newRequest.mainDocumentURL = request.mainDocumentURL
        newRequest.networkServiceType = request.networkServiceType
        return newRequest
    }

    func returnEmptyResponse() {
        // To block the load nicely, return an empty result to the client.
        // Nice => UIWebView's isLoading property gets set to false
        // Not nice => isLoading stays true while page waits for blocked items that never arrive

        // IIRC expectedContentLength of 0 is buggy (can't find the reference now).
        guard let url = request.url else { return }
        let response = URLResponse(url: url, mimeType: "text/html", expectedContentLength: 1, textEncodingName: "utf-8")
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    //a special artificial response that includes content that explains why the page was
    //blocked by phishing detection
    func returnBlockedPageResponse() {
        let path = Bundle.main.path(forResource: "SafeBrowsingError", ofType: "html")!
        let src = try! NSString(contentsOfFile: path, encoding: String.Encoding.utf8.rawValue) as String
        guard let url = request.url else { return }
        
        let blockedResponse = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "1.1", headerFields: nil)
        client?.urlProtocol(self, didReceive: blockedResponse!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: src.data(using: String.Encoding.utf8)!)
        client?.urlProtocolDidFinishLoading(self)
    }
    

    static var blankPixel: Data? = {
        let rect = CGRect(x: 0, y: 0, width: 1, height: 1)
        UIGraphicsBeginImageContext(rect.size)
        let c = UIGraphicsGetCurrentContext()
        c!.setFillColor(UIColor.clear.cgColor)
        c!.fill(rect)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return UIImageJPEGRepresentation(image!, 0.4)
    }()

    func returnBlankPixel() {
        guard let url = request.url, let pixel = URLProtocol.blankPixel else { return }
        let response = URLResponse(url: url, mimeType: "image/jpeg", expectedContentLength: pixel.count, textEncodingName: nil)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: pixel)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func startLoading() {
        let newRequest = URLProtocol.cloneRequest(request)
        Foundation.URLProtocol.setProperty(true, forKey: markerRequestHandled, in: newRequest)
        
        // We do not care about ad blocking for reader mode links, we just need to pass an authentication header.
        if let url = request.url, ReaderModeUtils.isReaderModeURL(url) {
            newRequest.addValue(WebServer.uniqueBytes, forHTTPHeaderField: WebServer.headerAuthKey)
            
            dataTask = session?.dataTask(with: newRequest as URLRequest)
            dataTask?.resume()
            return
        }

        let shieldState = URLProtocol.getShields(request)
        let ua = request.allHTTPHeaderFields?["User-Agent"]

        if shieldState.isOnSafeBrowsing() ?? false && SafeBrowsing.singleton.shouldBlock(request) {
            returnBlockedPageResponse()
            return
        } else if shieldState.isOnAdBlockAndTp() ?? false && (TrackingProtection.singleton.shouldBlock(request) || AdBlocker.singleton.shouldBlock(request)) {

            if request.url?.host?.contains("pcworldcommunication.d2.sc.omtrdc.net") ?? false || request.url?.host?.contains("b.scorecardresearch.com") ?? false {
                // sites such as macworld.com need this, or links are not clickable
                returnBlankPixel()
            } else {
                returnEmptyResponse()
            }
            let isBlockedByTP = TrackingProtection.singleton.shouldBlock(request)
            if let url = request.url?.absoluteString {
                postAsyncToMain(0.1) {
                    BrowserTabToUAMapper.userAgentToBrowserTab(ua)?.webView?.shieldStatUpdate(isBlockedByTP ? .tpIncrement : .abIncrement, increment: 1, affectedUrl: url)
                }
            }
            return
        } else if let url = request.url, let redirectedUrl = shieldState.isOnHTTPSE() ?? false ? HttpsEverywhere.singleton.tryRedirectingUrl(url) : nil {
            // TODO handle https redirect loop
            newRequest.url = redirectedUrl
            #if DEBUG
                //print(url.absoluteString + " [HTTPE to] " + redirectedUrl.absoluteString)
            #endif

            if url == request.mainDocumentURL {
                returnEmptyResponse()
                postAsyncToMain(0) {
                    BrowserTabToUAMapper.userAgentToBrowserTab(ua)?.webView?.loadRequest(newRequest as URLRequest)
                }
            } else {
                dataTask = session?.dataTask(with: newRequest as URLRequest)
                dataTask?.resume()
                postAsyncToMain(0.1) {
                    BrowserTabToUAMapper.userAgentToBrowserTab(ua)?.webView?.shieldStatUpdate(.httpseIncrement)
                }
            }
            return
        }

        disableJavascript = shieldState.isOnScriptBlocking() ?? false

        if let url = request.url?.absoluteString, disableJavascript && (url.contains(".js?") || url.contains(".js#") || url.endsWith(".js")) {
            returnEmptyResponse()
            return
        }

        if let customHeader = UserReferralProgram.shouldAddCustomHeader(for: request) {
            UrpLog.log("Adding custom header: [\(customHeader.field): \(customHeader.value)] for domain: \(request.url?.absoluteString ?? "404")")
            newRequest.addValue(customHeader.value, forHTTPHeaderField: customHeader.field)
        }

        dataTask = session?.dataTask(with: newRequest as URLRequest)
        dataTask?.resume()
    }

    override func stopLoading() {
        dataTask?.cancel()
        dataTask = nil
    }
}

// We need to implement those methods to handle urlprotocol correctly.
extension URLProtocol: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        client?.urlProtocol(self, didLoad: data)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let policy = URLCache.StoragePolicy(rawValue: request.cachePolicy.rawValue) ?? .notAllowed
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: policy)
        completionHandler(.allow)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        client?.urlProtocol(self, wasRedirectedTo: request, redirectResponse: response)
        completionHandler(request)
    }
    
    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        guard let error = error else { return }
        client?.urlProtocol(self, didFailWithError: error)
    }
    
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let protectionSpace = challenge.protectionSpace
        let sender = challenge.sender
        
        if protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            if let serverTrust = protectionSpace.serverTrust {
                let credential = URLCredential(trust: serverTrust)
                sender?.use(credential, for: challenge)
                completionHandler(.useCredential, credential)
                return
            }
        }
    }
    
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        client?.urlProtocolDidFinishLoading(self)
    }
}
