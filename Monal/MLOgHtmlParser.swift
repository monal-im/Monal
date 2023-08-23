//
//  ogHtmlParser.swift
//  Monal
//
//  Created by Friedrich Altheide on 27.06.22.
//  Copyright © 2022 Monal.im. All rights reserved.
//

import SwiftSoup;

@objc class MLOgHtmlParser: NSObject {
    var og_title: String?
    var og_image_url: URL?

    @objc init(html: String, andBaseUrl baseUrl: URL?) {
        super.init()
        do {
            let parsedSite: Document = try SwiftSoup.parse(html)
            
            self.og_title = try parsedSite.select("meta[property=og:title]").first()?.attr("content")
            if self.og_title == nil {
                self.og_title = try parsedSite.select("html head title").first()?.text()
            }
            if self.og_title == nil {
                DDLogWarn("Could not find any site title")
            }
            
            if let image_url = try parsedSite.select("meta[property=og:image]").first()?.attr("content").removingPercentEncoding {
                self.og_image_url = self.parseUrl(image_url, baseUrl)
            } else if let image_url = try parsedSite.select("html head link[rel=apple-touch-icon]").first()?.attr("href").removingPercentEncoding {
                self.og_image_url = self.parseUrl(image_url, baseUrl)
            } else if let image_url = try parsedSite.select("html head link[rel=icon]").first()?.attr("href").removingPercentEncoding {
                self.og_image_url = self.parseUrl(image_url, baseUrl)
            } else if let image_url = try parsedSite.select("html head link[rel=shortcut icon]").first()?.attr("href").removingPercentEncoding {
                self.og_image_url = self.parseUrl(image_url, baseUrl)
            } else {
                DDLogWarn("Could not find any site image")
            }
        } catch Exception.Error(let type, let message) {
            DDLogWarn("Could not parse html og elements: \(message) type: \(type)")
        } catch {
            DDLogWarn("Could not parse html og elements: unhandled exception")
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
