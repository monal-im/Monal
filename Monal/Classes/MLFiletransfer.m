//
//  MLFiletransfer.m
//  monalxmpp
//
//  Created by Thilo Molitor on 12.11.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MLConstants.h"
#import "MLFiletransfer.h"
#import "HelperTools.h"
#import "DataLayer.h"
#import "MLEncryptedPayload.h"
#import "xmpp.h"
#import "AESGcm.h"

@import MobileCoreServices;

static NSFileManager* fileManager;
static NSString* documentCache;

@implementation MLFiletransfer

+(void) initialize
{
    fileManager = [NSFileManager defaultManager];
    documentCache = [[[fileManager containerURLForSecurityApplicationGroupIdentifier:kAppGroup] path] stringByAppendingPathComponent:@"documentCache"];
    NSError* error;
    [fileManager createDirectoryAtURL:[NSURL fileURLWithPath:documentCache] withIntermediateDirectories:YES attributes:nil error:&error];
    if(error)
        @throw [NSException exceptionWithName:@"NSError" reason:[NSString stringWithFormat:@"%@", error] userInfo:@{@"error": error}];
    [HelperTools configureFileProtectionFor:documentCache];
}

+(void) checkMimeTypeAndSizeForHistoryID:(NSNumber*) historyId
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        DDLogDebug(@"Checking mime-type for historyID %@", historyId);
        MLMessage* msg = [[DataLayer sharedInstance] messageForHistoryID:historyId];
        if(!msg)
            return;
        NSString* url = [self genCanonicalUrl:msg.messageText];
        NSMutableURLRequest* request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:url]];
        request.HTTPMethod = @"HEAD";
        request.cachePolicy = NSURLRequestReturnCacheDataElseLoad;

        NSURLSession* session = [NSURLSession sharedSession];
        [[session dataTaskWithRequest:request completionHandler:^(NSData* _Nullable data, NSURLResponse* _Nullable response, NSError* _Nullable error) {
            NSDictionary* headers = ((NSHTTPURLResponse*)response).allHeaderFields;
            NSString* mimeType = [[headers objectForKey:@"Content-Type"] lowercaseString];
            NSNumber* contentLength = [headers objectForKey:@"Content-Length"] ? [NSNumber numberWithInt:([[headers objectForKey:@"Content-Length"] intValue])] : @(-1);
            if(!mimeType)
                mimeType = @"application/octet-stream";
            
            //try to deduce the content type from a given file extension if needed and possible
            if([mimeType isEqualToString:@"application/octet-stream"])
            {
                NSURLComponents* urlComponents = [NSURLComponents componentsWithString:url];
                if(urlComponents)
                    mimeType = [self getMimeTypeOfOriginalFile:urlComponents.path];
            }
            
            //update db with content type and size
            [[DataLayer sharedInstance] setMessageHistoryId:historyId filetransferMimeType:mimeType filetransferSize:contentLength];
            
            //send out update notification
            MLMessage* msg = [[DataLayer sharedInstance] messageForHistoryID:historyId];
            if(msg == nil)
            {
                DDLogError(@"Could not find msg for history ID %@!", historyId);
                return;
            }
            [[NSNotificationCenter defaultCenter] postNotificationName:kMonalMessageFiletransferUpdateNotice object:nil userInfo:@{@"message": msg}];
            
            //try to autodownload if sizes match
            //TODO JIM: these are the settings used for size checks and autodownload allowed checks
            if([[HelperTools defaultsDB] boolForKey:@"AutodownloadFiletransfers"] && [contentLength integerValue] <= [[HelperTools defaultsDB] integerForKey:@"AutodownloadFiletransfersMaxSize"])
                [self downloadFileForHistoryID:historyId];
        }] resume];
    });
}

+(void) downloadFileForHistoryID:(NSNumber*) historyId
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        MLMessage* msg = [[DataLayer sharedInstance] messageForHistoryID:historyId];
        if(!msg)
            return;
        NSString* url = [self genCanonicalUrl:msg.messageText];
        NSURLComponents* urlComponents = [NSURLComponents componentsWithString:msg.messageText];
        if(!urlComponents)
        {
            DDLogError(@"url components decoding failed");
            [self setErrorType:NSLocalizedString(@"Download error", @"") andErrorText:NSLocalizedString(@"Failed to decode download link", @"") forMessageId:msg.messageId];
            return;
        }
        
        NSURLSession* session = [NSURLSession sharedSession];
        NSURLSessionDownloadTask* task = [session downloadTaskWithURL:[NSURL URLWithString:url] completionHandler:^(NSURL* _Nullable location, NSURLResponse* _Nullable response, NSError* _Nullable error) {
            NSDictionary* headers = ((NSHTTPURLResponse*)response).allHeaderFields;
            NSString* mimeType = [[headers objectForKey:@"Content-Type"] lowercaseString];
            if(!mimeType)
                mimeType = @"application/octet-stream";
            
            //try to deduce the content type from a given file extension if needed and possible
            if([mimeType isEqualToString:@"application/octet-stream"])
                mimeType = [self getMimeTypeOfOriginalFile:urlComponents.path];
            
            NSString* cacheFile = [self getCacheFileNameForUrl:msg.messageText andMimeType:mimeType];
            
            //encrypted filetransfer
            if([urlComponents.scheme isEqualToString:@"aesgcm"])
            {
                if(urlComponents.fragment.length < 88)
                {
                    DDLogError(@"File download failed: %@", error);
                    [self setErrorType:NSLocalizedString(@"Download error", @"") andErrorText:NSLocalizedString(@"Failed to decode encrypted link", @"") forMessageId:msg.messageId];
                    return;
                }
                int ivLength = 24;
                //format is iv+32byte key
                NSData* key = [HelperTools dataWithHexString:[urlComponents.fragment substringWithRange:NSMakeRange(ivLength, 64)]];
                NSData* iv = [HelperTools dataWithHexString:[urlComponents.fragment substringToIndex:ivLength]];
                
                //decrypt data with given key and iv
                NSData* encryptedData = [NSData dataWithContentsOfURL:location];
                if(encryptedData && encryptedData.length > 0 && key && iv)
                {
                    NSData* decryptedData = [AESGcm decrypt:encryptedData withKey:key andIv:iv withAuth:nil];
                    [decryptedData writeToFile:cacheFile options:NSDataWritingAtomic error:&error];
                    if(error)
                    {
                        DDLogError(@"File download failed: %@", error);
                        [self setErrorType:NSLocalizedString(@"Download error", @"") andErrorText:NSLocalizedString(@"Failed to write decrypted download into cache directory", @"") forMessageId:msg.messageId];
                        return;
                    }
                    [HelperTools configureFileProtectionFor:cacheFile];
                }
            }
            else        //cleartext filetransfer
            {
                //copy file to our document cache
                [fileManager moveItemAtPath:[location path] toPath:cacheFile error:&error];
                if(error)
                {
                    DDLogError(@"File download failed: %@", error);
                    [self setErrorType:NSLocalizedString(@"Download error", @"") andErrorText:NSLocalizedString(@"Failed to copy downloaded file into cache directory", @"") forMessageId:msg.messageId];
                    return;
                }
                [HelperTools configureFileProtectionFor:cacheFile];
            }
            
            //update db with content type and size
            [[DataLayer sharedInstance] setMessageHistoryId:historyId filetransferMimeType:mimeType filetransferSize:@([[fileManager attributesOfItemAtPath:cacheFile error:nil] fileSize])];
            
            //send out update notification
            [[NSNotificationCenter defaultCenter] postNotificationName:kMonalMessageFiletransferUpdateNotice object:nil userInfo:@{@"message": msg}];
        }];
        [task resume];
    });
}

+(NSDictionary*) getFileInfoForMessage:(MLMessage*) msg
{
    if(![msg.messageType isEqualToString:kMessageTypeFiletransfer])
        return nil;
    NSString* cacheFile = [self loadCacheFileForUrl:msg.messageText andMimeType:msg.filetransferMimeType];
    if(!cacheFile)
        return nil;
    return @{
        @"url": msg.messageText,
        @"cacheId": [cacheFile lastPathComponent],
        @"cacheFile": cacheFile,
        @"mimeType": [self getMimeTypeOfCacheFile:cacheFile],
        @"size": @([[fileManager attributesOfItemAtPath:cacheFile error:nil] fileSize]),
    };
}

+(void) deleteFileForMessage:(MLMessage*) msg
{
    NSDictionary* info = [self getFileInfoForMessage:msg];
    if(info)
        [fileManager removeItemAtPath:info[@"cacheFile"] error:nil];
}

+(void) uploadFile:(NSURL*) fileUrl onAccount:(xmpp*) account withEncryption:(BOOL) encrypt andCompletion:(void (^)(NSString* _Nullable url, NSString* _Nullable mimeType, NSNumber* _Nullable size, NSError* _Nullable)) completion
{
    //copy file to our document cache (temporary filename because the upload url is unknown yet)
    NSString* tempname = [NSString stringWithFormat:@"%@.tmp", [[NSUUID UUID] UUIDString]];
    NSError* error;
    NSString* file = [documentCache stringByAppendingPathComponent:tempname];
    [fileManager copyItemAtPath:[fileUrl path] toPath:file error:&error];
    if(error)
    {
        [fileManager removeItemAtPath:file error:nil];      //remove temporary file
        DDLogError(@"File upload failed: %@", error);
        return completion(nil, nil, nil, error);
    }
    [HelperTools configureFileProtectionFor:file];
    
    [self internalUploadHandlerForTmpFile:file userFacingFilename:[fileUrl lastPathComponent] mimeType:[self getMimeTypeOfOriginalFile:[fileUrl path]] onAccount:account withEncryption:encrypt andCompletion:completion];
}

+(void) uploadUIImage:(UIImage*) image onAccount:(xmpp*) account withEncryption:(BOOL) encrypt andCompletion:(void (^)(NSString* _Nullable url, NSString* _Nullable mimeType, NSNumber* _Nullable size, NSError* _Nullable)) completion
{
    //copy file to our document cache (temporary filename because the upload url is unknown yet)
    NSString* tempname = [NSString stringWithFormat:@"%@.tmp", [[NSUUID UUID] UUIDString]];
    NSError* error;
    NSString* file = [documentCache stringByAppendingPathComponent:tempname];
    NSData* imageData = UIImageJPEGRepresentation(image, 0.75);     //TODO JIM: make this configurable in upload/download settings
    [imageData writeToFile:file options:NSDataWritingAtomic error:&error];
    if(error)
    {
        [fileManager removeItemAtPath:file error:nil];      //remove temporary file
        DDLogError(@"File upload failed: %@", error);
        return completion(nil, nil, nil, error);
    }
    [HelperTools configureFileProtectionFor:file];
    
    [self internalUploadHandlerForTmpFile:file userFacingFilename:[[NSUUID UUID] UUIDString] mimeType:@"image/jpeg" onAccount:account withEncryption:encrypt andCompletion:completion];
}

#pragma mark - internal methods

+(NSString*) loadCacheFileForUrl:(NSString*) url andMimeType:(NSString*) mimeType
{
    NSString* urlPart = [HelperTools hexadecimalString:[HelperTools sha256:[url dataUsingEncoding:NSUTF8StringEncoding]]];
    if(mimeType)
    {
        NSString* mimePart = [HelperTools hexadecimalString:[mimeType dataUsingEncoding:NSUTF8StringEncoding]];
        
        //the cache filename consists of a hash of the upload url (in hex) followed of the file mimetype (also in hex) as file extension
        NSString* cacheFile = [documentCache stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", urlPart, mimePart]];
        
        //file having the supplied mimeType exists
        if([fileManager fileExistsAtPath:cacheFile])
            return cacheFile;
    }
    
    //check for files having a different mime type but the same base url
    NSArray* directoryContents = [fileManager contentsOfDirectoryAtPath:documentCache error:nil];
    NSPredicate* filter = [NSPredicate predicateWithFormat:[NSString stringWithFormat:@"self BEGINSWITH '%@.'", urlPart]];
    for(NSString* file in [directoryContents filteredArrayUsingPredicate:filter])
        return [documentCache stringByAppendingPathComponent:file];
    
    //nothing found
    return nil;
}

+(NSString*) getCacheFileNameForUrl:(NSString*) url andMimeType:(NSString*) mimeType
{
    //the cache filename consists of a hash of the upload url (in hex) followed of the file mimetype (also in hex) as file extension
    NSString* urlPart = [HelperTools hexadecimalString:[HelperTools sha256:[url dataUsingEncoding:NSUTF8StringEncoding]]];
    NSString* mimePart = [HelperTools hexadecimalString:[mimeType dataUsingEncoding:NSUTF8StringEncoding]];
    return [documentCache stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", urlPart, mimePart]];
}

+(NSString*) genCanonicalUrl:(NSString*) url
{
    NSString* lowercaseURL = [url lowercaseString];
    if([lowercaseURL hasPrefix:@"aesgcm://"])
        url = [NSString stringWithFormat:@"https://%@", [url substringFromIndex:@"aesgcm://".length]];
    return url;
}

+(NSString*) getMimeTypeOfOriginalFile:(NSString*) file
{
    CFStringRef UTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)[file pathExtension], NULL);
    NSString* mimeType = (__bridge_transfer NSString*)UTTypeCopyPreferredTagWithClass(UTI, kUTTagClassMIMEType);
    CFRelease(UTI);
    return mimeType;
}

+(NSString*) getMimeTypeOfCacheFile:(NSString*) file
{
    return [[NSString alloc] initWithData:[HelperTools dataWithHexString:[file pathExtension]] encoding:NSUTF8StringEncoding];
}

+(void) setErrorType:(NSString*) errorType andErrorText:(NSString*) errorText forMessageId:(NSString*) messageId
{
    //update db
    [[DataLayer sharedInstance]
        setMessageId:messageId
        errorType:errorType
        errorReason:errorText
    ];
    
    //inform chatview of error
    [[NSNotificationCenter defaultCenter] postNotificationName:kMonalMessageErrorNotice object:nil userInfo:@{
        @"MessageID": messageId,
        @"errorType": errorType,
        @"errorReason": errorText
    }];
}

+(void) internalUploadHandlerForTmpFile:(NSString*) file userFacingFilename:(NSString*) userFacingFilename mimeType:(NSString*) mimeType onAccount:(xmpp*) account withEncryption:(BOOL) encrypted andCompletion:(void (^)(NSString* _Nullable url, NSString* _Nullable mimeType, NSNumber* _Nullable size, NSError* _Nullable)) completion
{
    //TODO: allow real file based transfers instead of NSData based transfers
    NSError* error;
    NSData* fileData = [[NSData alloc] initWithContentsOfFile:file options:0 error:&error];
    if(error)
    {
        [fileManager removeItemAtPath:file error:nil];      //remove temporary file
        DDLogError(@"File upload failed: %@", error);
        return completion(nil, nil, nil, error);
    }
    
    //encrypt data (TODO: do this in a streaming fashion, e.g. from file to tmpfile and stream this tmpfile via http afterwards)
    MLEncryptedPayload* encryptedPayload;
    if(encrypted)
    {
        encryptedPayload = [AESGcm encrypt:fileData keySize:32];
        if(encryptedPayload)
        {
            NSMutableData* encryptedData = [encryptedPayload.body mutableCopy];
            [encryptedData appendData:encryptedPayload.authTag];
            fileData = encryptedData;
        }
        else
        {
            NSError* error = [NSError errorWithDomain:@"MonalError" code:0 userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"Failed to encrypt file", @"")}];
            [fileManager removeItemAtPath:file error:nil];      //remove temporary file
            DDLogError(@"File upload failed: %@", error);
            return completion(nil, nil, nil, error);
        }
    }
    
    [account requestHTTPSlotWithParams:@{
        kData:fileData,
        kFileName:userFacingFilename,
        kContentType:mimeType
    } andCompletion:^(NSString *url, NSError *error) {
        NSURLComponents* urlComponents = [NSURLComponents componentsWithURL:[NSURL URLWithString:url] resolvingAgainstBaseURL:NO];
        if(url && urlComponents)
        {
            //build aesgcm url containing "aesgcm" url-scheme and IV and AES-key in urlfragment
            if(encrypted)
            {
                urlComponents.scheme = @"aesgcm";
                urlComponents.fragment = [NSString stringWithFormat:@"%@%@",
                                        [HelperTools hexadecimalString:encryptedPayload.iv],
                                        //extract real aes key without authtag (32 bytes = 256bit)
                                        //TODO: DOES THIS MAKE SENSE (WHY NO AUTH TAG??)
                                        //[HelperTools hexadecimalString:[encryptedPayload.key subdataWithRange:NSMakeRange(0, 32)]]];
                                        [HelperTools hexadecimalString:encryptedPayload.key]];
                url = urlComponents.string;
            }

            //move the tempfile to our cache location
            NSString* cacheFile = [self getCacheFileNameForUrl:url andMimeType:mimeType];
            [fileManager moveItemAtPath:file toPath:cacheFile error:&error];
            if(error)
            {
                NSError* error = [NSError errorWithDomain:@"MonalError" code:0 userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"Failed to uploaded file to file cache directory", @"")}];
                [fileManager removeItemAtPath:file error:nil];      //remove temporary file
                DDLogError(@"File upload failed: %@", error);
                return completion(nil, nil, nil, error);
            }
            [HelperTools configureFileProtectionFor:cacheFile];
            
            return completion(url, mimeType, [NSNumber numberWithInteger:fileData.length], nil);
        }
        else
        {
            NSError* error = [NSError errorWithDomain:@"MonalError" code:0 userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"Failed to parse URL returned by HTTP upload server", @"")}];
            [fileManager removeItemAtPath:file error:nil];      //remove temporary file
            DDLogError(@"File upload failed: %@", error);
            return completion(nil, nil, nil, error);
        }
    }];
}

@end
