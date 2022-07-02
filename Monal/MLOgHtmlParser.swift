//
//  ogHtmlParser.swift
//  Monal
//
//  Created by Friedrich Altheide on 27.06.22.
//  Copyright © 2022 Monal.im. All rights reserved.
//

import Foundation
import SwiftSoup;
import CocoaLumberjack

@objc class MLOgHtmlParser: NSObject {
    var og_title: String?
    var og_image_url: URL?

    @objc init(html: String) {
        do {
            let parsedSite: Document = try SwiftSoup.parse(html)
            self.og_title = try parsedSite.select("meta[property=og:title]").first()?.attr("content")
            if let image_url = try parsedSite.select("meta[property=og:image]").first()?.attr("content").removingPercentEncoding {
                self.og_image_url = URL.init(string: image_url)?.absoluteURL;
            }
        } catch Exception.Error(let type, let message) {
            DDLogError("Could not parse html og elements: \(message) type: \(type)")
        } catch {
            DDLogError("Could not parse html og elements: unhandled exception")
        }
    }

    @objc func getOgTitle() -> String? {
        self.og_title
    }

    @objc func getOgImage() -> URL? {
        self.og_image_url
    }
}
