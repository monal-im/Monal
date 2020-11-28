//
//  MLFiletransfer.m
//  monalxmpp
//
//  Created by Thilo Molitor on 12.11.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MLFiletransfer.h"
#import "MLConstants.h"
#import "DataLayer.h"
#import "HelperTools.h"

@import MobileCoreServices;

@implementation MLFiletransfer

+(void) checkMimeTypeAndSizeForHistoryID:(NSNumber*) historyId withURL:(NSString*) url
{
    DDLogDebug(@"Checking mime-type for historyID %@", historyId);
    url = [self genCanonicalUrl:url];
    NSMutableURLRequest* request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:url]];
    request.HTTPMethod = @"HEAD";
    request.cachePolicy = NSURLRequestReturnCacheDataElseLoad;

    NSURLSession* session = [NSURLSession sharedSession];
    [[session dataTaskWithRequest:request completionHandler:^(NSData* _Nullable data, NSURLResponse* _Nullable response, NSError* _Nullable error) {
        NSDictionary* headers = ((NSHTTPURLResponse*)response).allHeaderFields;
        NSString* contentType = [[headers objectForKey:@"Content-Type"] lowercaseString];
        NSNumber* contentLength = [headers objectForKey:@"Content-Length"] ? [NSNumber numberWithInt:([[headers objectForKey:@"Content-Length"] intValue])] : @(-1);
        if(!contentType)
            contentType = @"application/octet-stream";
        
        //try to deduce the content type from a given file extension if needed and possible
        if([contentType isEqualToString:@"application/octet-stream"])
        {
            NSURLComponents* urlComponents = [NSURLComponents componentsWithString:url];
            if(urlComponents)
            {
                CFStringRef UTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)[urlComponents.path pathExtension], NULL);
                contentType = (__bridge_transfer NSString*)(UTTypeCopyPreferredTagWithClass (UTI, kUTTagClassMIMEType));
                CFRelease(UTI);
            }
        }
        
        //update db with content type and size
        [[DataLayer sharedInstance] setMessageHistoryId:historyId filetransferMimeType:contentType filetransferSize:contentLength];
        
        //send out update notification
        NSArray* msgList = [[DataLayer sharedInstance] messagesForHistoryIDs:@[historyId]];
        if(![msgList count])
        {
            DDLogError(@"Could not find msg for history ID %@!", historyId);
            return;
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:kMonalMessageFiletransferUpdateNotice object:nil userInfo:@{@"message": msgList[0]}];
        
        //try to autodownload if sizes match
        //TODO JIM: these are the settings used for size checks and autodownload allowed checks
        if([[HelperTools defaultsDB] boolForKey:@"AutodownloadFiletransfers"] && [contentLength integerValue] <= [[HelperTools defaultsDB] integerForKey:@"AutodownloadFiletransfersMaxSize"])
            [self downloadFileForHistoryID:historyId withURL:url];
    }] resume];
}

+(void) downloadFileForHistoryID:(NSNumber*) historyId withURL:(NSString*) url
{
    DDLogError(@"TO IMPLEMENT: FILE DOWNLOAD!");
}

+(NSString*) genCanonicalUrl:(NSString*) url
{
    NSString* lowercaseURL = [url lowercaseString];
    if([lowercaseURL hasPrefix:@"aesgcm://"])
        url = [NSString stringWithFormat:@"https://%@", [url substringFromIndex:@"aesgcm://".length]];
    return url;
}

@end
