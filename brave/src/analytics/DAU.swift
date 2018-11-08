/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared

// TODO: Separate logger for this kind of work?
private let log = Logger.browserLogger

// Unit tests for DAU are located in brave/tests_src/unit/DauTest.swift.
struct DAU {
    public static let preferencesKey = "dau_stat"
    public static let lastPingFirstMondayKey = "lastPingFirstMondayKey"
    public static let weekOfInstallationKeyPrefKey = "week_of_installation"
    
    /// Default installation date for legacy woi version.
    public static let defaultWoiDate = "2016-01-04"
    
    let prefs: Prefs
    
    private let baseUrl = "https://laptop-updates.brave.com/1/usage/ios?platform=ios"
    
    private let today: Date
    
    /// We always use gregorian calendar for DAU pings. This also adds more anonymity to the server call.
    fileprivate static var calendar: NSCalendar { return Calendar(identifier: .gregorian) as NSCalendar }
    
    private var todayComponents: DateComponents {
        return DAU.calendar.components([.day, .month , .year, .weekday], from: today)
    }
    
    init(prefs: Prefs, date: Date? = nil) {
        self.prefs = prefs
        today = date ?? Date()
    }
    
    public func sendPingToServer() {
        guard let params = paramsAndPrefsSetup() else {
            log.debug("dau, no changes detected, no server ping")
            return
        }
        
        // Sending ping to server
        let fullUrl = baseUrl + params
        log.debug("send ping to server, url: \(fullUrl)")
        
        guard let url = URL(string: fullUrl) else {
            if !BraveUX.IsRelease {
                BraveApp.showErrorAlert(title: "Debug", error: "failed stats update")
            }
            return
        }
        let task = URLSession.shared.dataTask(with: url) { _, _, error in
            if let e = error { log.error("status update error: \(e)") }
        }
        task.resume()
    }
    
    
    /** Return params query or nil if no ping should be send to server. */
    func paramsAndPrefsSetup() -> String? {
        let dauStats = prefs.arrayForKey(DAU.preferencesKey)
        let isFirstLaunch = dauStats == nil
        
        var params
            = channelParam
            + versionParam
        
        func setInstallWeek(installWeek: String) {
            prefs.setString(installWeek, forKey: DAU.weekOfInstallationKeyPrefKey)
        }
        
        // Setting preferences
        if isFirstLaunch {
            setInstallWeek(installWeek: todayComponents.weeksMonday)
        } else if prefs.stringForKey(DAU.weekOfInstallationKeyPrefKey) == nil {
            // User is upgrading (app already installed), but we have never set a weekInstallKey
            setInstallWeek(installWeek: DAU.defaultWoiDate)
        }
        
        // If not first launch, ping to the server is only sent after enough time passed
        guard let dauStatParams = dauStatParams(dauStats, firstLaunch: isFirstLaunch) else {
            log.debug("dau, no changes detected, no server ping")
            return nil
        }
        
        params
            += dauStatParams
            + firstLaunchParam(isFirstLaunch)
            // Must be after setting up the preferences
            + weekOfInstallationParam

        // MARK: User referrals

        if let referralCode = UserReferralProgram.getReferralCode(prefs: prefs) {
            params += "&ref=\(referralCode)"
            UrpLog.log("DAU ping with added ref, params: \(params)")
        }
        
        // This preference is used to calculate wheter user used the app in this month and/or day.
        let secsMonthYear = [Int(today.timeIntervalSince1970), todayComponents.month, todayComponents.year]
        prefs.setObject(secsMonthYear, forKey: DAU.preferencesKey)
        
        // Using `secsMonthYear` with week component for weekly usage check is not robust enough and fails on edge cases.
        // To calculate weekly usage we store first monday of week to and then compare it with the
        // current first monday of week to see if a user used the app on new week.
        let lastPingFirstMonday = todayComponents.weeksMonday
        prefs.setObject(lastPingFirstMonday, forKey: DAU.lastPingFirstMondayKey)
        
        return params
    }
    
    var channelParam: String {
        return "&channel=\(BraveUX.IsRelease ? "stable" : "beta")"
    }
    
    var versionParam: String {
        var version = AppInfo.appVersion
        
        if DAU.shouldAppend0ToAppVersion(version) {
            version += ".0"
        }
        
        return "&version=\(version)"
    }

    /// All app versions for dau pings must be saved in x.x.x format where x are digits.
    static func shouldAppend0ToAppVersion(_ version: String) -> Bool {
        let correctAppVersionPattern = "^\\d+.\\d+$"
        do {
            let regex = try NSRegularExpression(pattern: correctAppVersionPattern, options: [])
            let match = regex.firstMatch(in: version, options: [], range: NSRange(location: 0, length: version.count))
            
            return match != nil
        } catch {
            log.error("Version regex pattern error")
            return false
        }
    }
    
    func firstLaunchParam(_ isFirst: Bool) -> String {
        return "&first=\(isFirst)"
    }
    
    /** All first app installs are normalized to first day of the week.
     Eg. user installs app on wednesday 2017-22-11, his install date is recorded as of 2017-20-11(Monday) */
    var weekOfInstallationParam: String {
        guard let woi = prefs.stringForKey(DAU.weekOfInstallationKeyPrefKey) else {
            log.error("woi, is nil")
            return ""
        }
        return "&woi=\(woi)"
    }
    
    /// Returns nil if no dau changes detected.
    func dauStatParams(_ dauStat: [Any]?, firstLaunch isFirstLaunch: Bool) -> String? {
        func dauParams(_ daily: Bool, _ weekly: Bool, _ monthly: Bool) -> String {
            return "&daily=\(daily)&weekly=\(weekly)&monthly=\(monthly)"
        }
        
        if isFirstLaunch {
            return dauParams(true, true, true)
        }
        
        let month = todayComponents.month
        let year = todayComponents.year
        
        guard let stat = dauStat as? [Int] else {
            log.error("Cannot cast dauStat to [Int]")
            return nil
        }
        
        guard stat.count == 3 else {
            log.error("dauStat array must contain exactly 3 elements")
            return nil
        }
        
        let dSecs = Int(today.timeIntervalSince1970) - stat[0]
        let _month = stat[1]
        let _year = stat[2]
        let SECONDS_IN_A_DAY = 86400
        
        // On first launch, the user is all three of these
        let daily = dSecs >= SECONDS_IN_A_DAY
        
        let weeksMonday = prefs.stringForKey(DAU.lastPingFirstMondayKey)
        // There is no lastPingFirstMondayKey preference set at first launch, meaning the week param should be set to true.
        let isFirstLaunchWeeksMonday = weeksMonday == nil
        let weekly = todayComponents.weeksMonday != weeksMonday || isFirstLaunchWeeksMonday
        
        let monthly = month != _month || year != _year
        
        log.debug("Dau stat params, daily: \(daily), weekly: \(weekly), monthly:\(monthly), dSecs: \(dSecs)")
        if (!daily && !weekly && !monthly) {
            // No changes, no ping
            return nil
        }
        
        return dauParams(daily, weekly, monthly)
    }
}

extension DateComponents {
    /// Returns date of current week's monday in YYYY-MM-DD format
    var weeksMonday: String {
        var isSunday: Bool {
            guard let weekday = weekday else {
                log.error("Weekday is nil")
                return false
            }
            return weekday == 1
        }
        
        // Make sure all required date components are set.
        guard let _ = day, let _ = month, let _ = year, let weekday = weekday else {
            log.error("Date components are missing")
            return ""
        }
        
        guard let today = DAU.calendar.date(from: self) else {
            log.error("Cannot create date from date components")
            return ""
        }
        
        let dayInSeconds = 60 * 60 * 24
        // Sunday is first weekday so we need to handle this day differently, can't just substract it.
        let sundayToMondayDayDifference = 6
        let dayDifference = isSunday ? sundayToMondayDayDifference : weekday - 2 // -2 because monday is second weekday
        
        let monday = Date(timeInterval: -TimeInterval(dayDifference * dayInSeconds), since: today)
        let mondayComponents = DAU.calendar.components([.day, .month , .year], from: monday)
        
        guard let mYear = mondayComponents.year, let mMonth = mondayComponents.month, let mDay = mondayComponents.day else {
            log.error("First monday of the week components are nil")
            return ""
        }
        
        return "\(mYear)-\(mMonth)-\(mDay)"
    }
}
