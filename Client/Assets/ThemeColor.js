/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */


if (!window.__firefox__) {
    window.__firefox__ = {};
}

window.__firefox__.sitecolor = function() {
    const rgbaFromStr = function (rgba) {
        if (!rgba) {
            return undefined
        }
        return rgba.split('(')[1].split(')')[0].split(',')
    }
    
    const distance = function (v1, v2) {
        let d = 0
        for (let i = 0; i < v2.length; i++) {
            d += (v1[i] - v2[i]) * (v1[i] - v2[i])
        }
        return Math.sqrt(d)
    }
    
    const getElementColor = function (el) {
        const currentColorRGBA = window.getComputedStyle(el).backgroundColor
        const currentColor = rgbaFromStr(currentColorRGBA)
        
        // Ensure that the selected color is not too similar to an inactive tab color
        const threshold = 50
        if (currentColor !== undefined &&
            Number(currentColor[3]) !== 0 &&
            distance(currentColor, [199, 199, 199]) > threshold) {
            return currentColorRGBA
        }
        return undefined
    }
    
    // Determines a good tab color
    const computeThemeColor = function () {
        // use y=1 vs y=3(desktop) since mobile sites typically have smaller headers.
        const samplePoints = [[3, 1], [window.innerWidth / 2, 1], [window.innerWidth - 3, 1]]
        const els = []
        for (const point of samplePoints) {
            const el = document.elementFromPoint(point[0], point[1])
            if (el) {
                els.push(el)
                if (el.parentElement) {
                    els.push(el.parentElement)
                }
            }
        }
        els.push(document.body)
        for (const el of els) {
            if (el !== document.documentElement && el instanceof window.Element) {
                const themeColor = getElementColor(el)
                if (themeColor) {
                    return {themeColor}
                }
            }
        }
        return undefined
    }
    
    const metaValue = function(meta) {
        var metas = document.getElementsByTagName('meta');
        for (var i=0; i<metas.length; i++) {
            if (metas[i].getAttribute("property") == meta) {
                return metas[i].getAttribute("content");
            }
        }
        return undefined
    }
    
    function getSiteColor() {
        var themeColor;
        if (metaValue("theme-color")) {
            themeColor = metaValue("theme-color");
            themeColor = {themeColor};
        }
        else if (metaValue("msapplication-navbutton-color")) {
            themeColor = metaValue("msapplication-navbutton-color");
            themeColor = {themeColor};
        }
        else if (metaValue("apple-mobile-web-app-status-bar-style")) {
            themeColor = metaValue("apple-mobile-web-app-status-bar-style");
            themeColor = {themeColor};
        }
        else {
            themeColor = computeThemeColor();
        }
        
        __bravejs___siteColorMessageHandler(themeColor);
    }
    
    return {
        getSiteColor : getSiteColor
    };
    
}();
