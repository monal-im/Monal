//
//  ogHtmlParser.swift
//  Monal
//
//  Created by Friedrich Altheide on 27.06.22.
//  Copyright © 2022 Monal.im. All rights reserved.
//

@objc class MLOgHtmlParser: NSObject {
    var og_title: String?
    var og_image_url: URL?

    @objc init(html: String, andBaseUrl baseUrl: URL?) {
        super.init()
        let parsedSite = HtmlParserBridge(html:html)
        
        self.og_title = try? parsedSite.select("meta[property=og\\:title]", attribute:"content").first
        if self.og_title == nil {
            self.og_title = try? parsedSite.select("html head title").first
        }
        if self.og_title == nil {
            DDLogWarn("Could not find any site title")
        }
        
        if let image_url = try? parsedSite.select("meta[property=og\\:image]", attribute:"content").first?.removingPercentEncoding {
            self.og_image_url = self.parseUrl(image_url, baseUrl)
        } else if let image_url = try? parsedSite.select("html head link[rel=apple-touch-icon]", attribute:"href").first?.removingPercentEncoding {
            self.og_image_url = self.parseUrl(image_url, baseUrl)
        } else if let image_url = try? parsedSite.select("html head link[rel=icon]", attribute:"href").first?.removingPercentEncoding {
            self.og_image_url = self.parseUrl(image_url, baseUrl)
        } else if let image_url = try? parsedSite.select("html head link[rel=shortcut icon]", attribute:"href").first?.removingPercentEncoding {
            self.og_image_url = self.parseUrl(image_url, baseUrl)
        } else {
            DDLogWarn("Could not find any site image in html")
        }
    }
    
    private func parseUrl(_ url: String, _ baseUrl: URL?) -> URL? {
        if url.hasPrefix("http") {
            return URL.init(string:url)?.absoluteURL
        } else if let baseUrl = baseUrl {
            return URL.init(string:url, relativeTo:baseUrl)?.absoluteURL
        }
        return nil
    }

    @objc func getOgTitle() -> String? {
        self.og_title
    }

    @objc func getOgImage() -> URL? {
        self.og_image_url
    }
}
