/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Shared

extension BrowserViewController {
    @objc func reloadTab(){
        if homePanelController == nil {
            tabManager.selectedTab?.reload()
        }
    }

    @objc func goBack(){
        if tabManager.selectedTab?.canGoBack == true && homePanelController == nil {
            tabManager.selectedTab?.goBack()
        }
    }
    @objc func goForward(){
        if tabManager.selectedTab?.canGoForward == true && homePanelController == nil {
            tabManager.selectedTab?.goForward()
        }
    }

    @objc func findOnPage(){
        if let tab = tabManager.selectedTab, homePanelController == nil {
            browser(tab, didSelectFindInPageForSelection: "")
        }
    }

    @objc func selectLocationBar() {
        urlBar.browserLocationViewDidTapLocation(urlBar.locationView)
    }

    @objc func newTab() {
        openBlankNewTabAndFocus(isPrivate: PrivateBrowsing.singleton.isOn)
        self.selectLocationBar()
    }

    @objc func newPrivateTab() {
        openBlankNewTabAndFocus(isPrivate: true)
        let profile = getApp().profile
        if PinViewController.isBrowserLockEnabled && profile?.prefs.boolForKey(kPrefKeyPopupForDDG) == true {
            self.selectLocationBar()
        }
    }

    @objc func closeTab() {
        guard let tab = tabManager.selectedTab else { return }
        let priv = tab.isPrivate
        nextOrPrevTabShortcut(false)
        tabManager.removeTab(tab, createTabIfNoneLeft: !priv)
        if priv && tabManager.tabs.privateTabs.count == 0 {
            urlBarDidPressTabs(urlBar)
        }
    }

    fileprivate func nextOrPrevTabShortcut(_ isNext: Bool) {
        guard let tab = tabManager.selectedTab else { return }
        let step = isNext ? 1 : -1
        let tabList: [Browser] = tabManager.tabs.displayedTabsForCurrentPrivateMode
        func wrappingMod(_ val:Int, mod:Int) -> Int {
            return ((val % mod) + mod) % mod
        }
        assert(wrappingMod(-1, mod: 10) == 9)
        let index = wrappingMod((tabList.index(of: tab)! + step), mod: tabList.count)
        tabManager.selectTab(tabList[index])
    }

    @objc func nextTab() {
        nextOrPrevTabShortcut(true)
    }

    @objc func previousTab() {
        nextOrPrevTabShortcut(false)
    }

    override var keyCommands: [UIKeyCommand]? {
        let result =  [
            UIKeyCommand(input: "r", modifierFlags: .command, action: #selector(BrowserViewController.reloadTab), discoverabilityTitle: Strings.ReloadPageTitle),
            UIKeyCommand(input: "[", modifierFlags: .command, action: #selector(BrowserViewController.goBack), discoverabilityTitle: Strings.BackTitle),
            UIKeyCommand(input: "]", modifierFlags: .command, action: #selector(BrowserViewController.goForward), discoverabilityTitle: Strings.ForwardTitle),

            UIKeyCommand(input: "f", modifierFlags: .command, action: #selector(BrowserViewController.findOnPage), discoverabilityTitle: Strings.FindTitle),
            UIKeyCommand(input: "l", modifierFlags: .command, action: #selector(BrowserViewController.selectLocationBar), discoverabilityTitle: Strings.SelectLocationBarTitle),
            UIKeyCommand(input: "t", modifierFlags: .command, action: #selector(BrowserViewController.newTab), discoverabilityTitle: Strings.NewTabTitle),
            //#if DEBUG
                UIKeyCommand(input: "t", modifierFlags: .control, action: #selector(BrowserViewController.newTab), discoverabilityTitle: Strings.NewTabTitle),
            //#endif
            UIKeyCommand(input: "p", modifierFlags: [.command, .shift], action: #selector(BrowserViewController.newPrivateTab), discoverabilityTitle: Strings.NewPrivateTabTitle),
            UIKeyCommand(input: "w", modifierFlags: .command, action: #selector(BrowserViewController.closeTab), discoverabilityTitle: Strings.CloseTabTitle),
            UIKeyCommand(input: "\t", modifierFlags: .control, action: #selector(BrowserViewController.nextTab), discoverabilityTitle: Strings.ShowNextTabTitle),
            UIKeyCommand(input: "\t", modifierFlags: [.control, .shift], action: #selector(BrowserViewController.previousTab), discoverabilityTitle: Strings.ShowPreviousTabTitle),
        ]
        #if DEBUG
            // in simulator, CMD+t is slow-mo animation
            return result + [
                UIKeyCommand(input: "t", modifierFlags: [.command, .shift], action: #selector(BrowserViewController.newTab))]
        #else
            return result
        #endif
    }
}
