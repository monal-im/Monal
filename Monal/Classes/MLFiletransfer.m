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
        DDLogInfo(@"Requesting mime-type and size for historyID %@ from http server", historyId);
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
            if(!mimeType)       //default mime type if none was returned by http server
                mimeType = @"application/octet-stream";
            
            //try to deduce the content type from a given file extension if needed and possible
            if([mimeType isEqualToString:@"application/octet-stream"])
            {
                NSURLComponents* urlComponents = [NSURLComponents componentsWithString:url];
                if(urlComponents)
                    mimeType = [self getMimeTypeOfOriginalFile:urlComponents.path];
            }
            
            //make sure we *always* have a mime type
            if(!mimeType)
                mimeType = @"application/octet-stream";
            
            DDLogInfo(@"Got http mime-type and size for historyID %@: %@ (%@)", historyId, mimeType, contentLength);
            DDLogDebug(@"Updating db and sending out kMonalMessageFiletransferUpdateNotice");
            
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
            {
                DDLogInfo(@"Autodownloading file");
                [self downloadFileForHistoryID:historyId];
            }
        }] resume];
    });
}

+(void) downloadFileForHistoryID:(NSNumber*) historyId
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        DDLogInfo(@"Downloading file for historyID %@", historyId);
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
            
            //make sure we *always* have a mime type
            if(!mimeType)
                mimeType = @"application/octet-stream";
            
            NSString* cacheFile = [self calculateCacheFileForNewUrl:msg.messageText andMimeType:mimeType];
            
            //encrypted filetransfer
            if([[urlComponents.scheme lowercaseString] isEqualToString:@"aesgcm"])
            {
                DDLogInfo(@"Decrypting encrypted filetransfer");
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
                DDLogInfo(@"Copying downloaded file to document cache at %@", cacheFile);
                [fileManager moveItemAtPath:[location path] toPath:cacheFile error:&error];
                if(error)
                {
                    DDLogError(@"File download failed: %@", error);
                    [self setErrorType:NSLocalizedString(@"Download error", @"") andErrorText:NSLocalizedString(@"Failed to copy downloaded file into cache directory", @"") forMessageId:msg.messageId];
                    return;
                }
                [HelperTools configureFileProtectionFor:cacheFile];
            }
            
            DDLogDebug(@"Updating db and sending out kMonalMessageFiletransferUpdateNotice");
            
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
    NSURLComponents* urlComponents = [NSURLComponents componentsWithString:msg.messageText];
    NSString* filename = [[NSUUID UUID] UUIDString];       //default is a dummy filename (used when the filename can not be extracted from url)
    if(urlComponents != nil && urlComponents.path)
        filename = [urlComponents.path lastPathComponent];
    NSString* cacheFile = [self retrieveCacheFileForUrl:msg.messageText andMimeType:(msg.filetransferMimeType && ![msg.filetransferMimeType isEqualToString:@""] ? msg.filetransferMimeType : nil)];
    if(!cacheFile)
        return @{
            @"url": msg.messageText,
            @"filename": filename,
            @"needsDownloading": @YES,
        };
    return @{
        @"url": msg.messageText,
        @"filename": filename,
        @"cacheId": [cacheFile lastPathComponent],
        @"cacheFile": cacheFile,
        @"needsDownloading": @NO,
        @"mimeType": [self getMimeTypeOfCacheFile:cacheFile],
        @"size": @([[fileManager attributesOfItemAtPath:cacheFile error:nil] fileSize]),
    };
}

+(void) deleteFileForMessage:(MLMessage*) msg
{
    if(![msg.messageType isEqualToString:kMessageTypeFiletransfer])
        return;
    DDLogInfo(@"Deleting file for url %@", msg.messageText);
    NSDictionary* info = [self getFileInfoForMessage:msg];
    if(info)
    {
        DDLogDebug(@"Deleting file in cache: %@", info[@"cacheFile"]);
        [fileManager removeItemAtPath:info[@"cacheFile"] error:nil];
    }
}

+(void) uploadFile:(NSURL*) fileUrl onAccount:(xmpp*) account withEncryption:(BOOL) encrypt andCompletion:(void (^)(NSString* _Nullable url, NSString* _Nullable mimeType, NSNumber* _Nullable size, NSError* _Nullable error)) completion
{
    DDLogInfo(@"Uploading file stored at %@", [fileUrl path]);
    
    //copy file to our document cache (temporary filename because the upload url is unknown yet)
    NSString* tempname = [NSString stringWithFormat:@"%@.tmp", [[NSUUID UUID] UUIDString]];
    NSError* error;
    NSString* file = [documentCache stringByAppendingPathComponent:tempname];
    DDLogDebug(@"Tempstoring file at %@", file);
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

+(void) uploadUIImage:(UIImage*) image onAccount:(xmpp*) account withEncryption:(BOOL) encrypt andCompletion:(void (^)(NSString* _Nullable url, NSString* _Nullable mimeType, NSNumber* _Nullable size, NSError* _Nullable error)) completion
{
    double jpegQuality = 0.75;          //TODO JIM: make this configurable in upload/download settings
    
    DDLogInfo(@"Uploading image from UIImage object");
    
    //copy file to our document cache (temporary filename because the upload url is unknown yet)
    NSString* tempname = [NSString stringWithFormat:@"%@.tmp", [[NSUUID UUID] UUIDString]];
    NSError* error;
    NSString* file = [documentCache stringByAppendingPathComponent:tempname];
    DDLogDebug(@"Tempstoring jpeg encoded file having quality %f at %@", jpegQuality, file);
    NSData* imageData = UIImageJPEGRepresentation(image, jpegQuality);
    [imageData writeToFile:file options:NSDataWritingAtomic error:&error];
    if(error)
    {
        [fileManager removeItemAtPath:file error:nil];      //remove temporary file
        DDLogError(@"File upload failed: %@", error);
        return completion(nil, nil, nil, error);
    }
    [HelperTools configureFileProtectionFor:file];
    
    [self internalUploadHandlerForTmpFile:file userFacingFilename:[NSString stringWithFormat:@"%@.jpg", [[NSUUID UUID] UUIDString]] mimeType:@"image/jpeg" onAccount:account withEncryption:encrypt andCompletion:completion];
}

+(void) doStartupCleanup
{
    //delete leftover tmp files
    NSArray* directoryContents = [fileManager contentsOfDirectoryAtPath:documentCache error:nil];
    NSPredicate* filter = [NSPredicate predicateWithFormat:@"self ENDSWITH '.tmp'"];
    for(NSString* file in [directoryContents filteredArrayUsingPredicate:filter])
    {
        DDLogInfo(@"Deleting leftover tmp file at %@", [documentCache stringByAppendingPathComponent:file]);
        [fileManager removeItemAtPath:[documentCache stringByAppendingPathComponent:file] error:nil];
    }
    
    //*** migrate old image store to new fileupload store if needed***
    if(![[HelperTools defaultsDB] boolForKey:@"ImageCacheMigratedToFiletransferCache"])
    {
        DDLogInfo(@"Migrating old image store to new filetransfer cache");
        
        //first of all upgrade all message types (needed to make getFileInfoForMessage: work later on)
        [[DataLayer sharedInstance] upgradeImageMessagesToFiletransferMessages];
        
        //copy all images listed in old imageCache db tables to our new filetransfer store
        NSArray* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString* documentsDirectory = [paths objectAtIndex:0];
        NSString* cachePath = [documentsDirectory stringByAppendingPathComponent:@"imagecache"];
        for(NSDictionary* img in [[DataLayer sharedInstance] getAllCachedImages])
        {
            //extract old url, file and mime type
            NSURLComponents* urlComponents = [NSURLComponents componentsWithString:img[@"url"]];
            if(!urlComponents)
                continue;
            NSString* mimeType = [self getMimeTypeOfOriginalFile:urlComponents.path];
            NSString* oldFile = [cachePath stringByAppendingPathComponent:img[@"path"]];
            NSString* newFile = [self calculateCacheFileForNewUrl:img[@"url"] andMimeType:mimeType];
            
            DDLogInfo(@"Migrating old image cache file %@ (having mimeType %@) for URL %@ to new cache at %@", oldFile, mimeType, img[@"url"], newFile);
            if([fileManager fileExistsAtPath:oldFile])
            {
                [fileManager copyItemAtPath:oldFile toPath:newFile error:nil];
                [HelperTools configureFileProtectionFor:newFile];
                [fileManager removeItemAtPath:oldFile error:nil];
            }
            else
                DDLogWarn(@"Old file not existing --> not moving file, but still updating db entries");
            
            //update every history_db entry with new filetransfer metadata
            //(this will flip the message type to kMessageTypeFiletransfer and set correct mimeType and size values)
            NSArray* messageList = [[DataLayer sharedInstance] getAllMessagesForFiletransferUrl:img[@"url"]];
            if(![messageList count])
            {
                DDLogWarn(@"No messages in history db having this url, deleting file completely");
                [fileManager removeItemAtPath:newFile error:nil];
            }
            else
            {
                DDLogInfo(@"Updating every history db entry with new filetransfer metadata: %lu messages", [messageList count]);
                for(MLMessage* msg in messageList)
                {
                    NSDictionary* info = [self getFileInfoForMessage:msg];
                    DDLogDebug(@"FILETRANSFER INFO: %@", info);
                    //don't update mime type and size if we still need to download the file (both is unknown in this case)
                    if(info && ![info[@"needsDownloading"] boolValue])
                        [[DataLayer sharedInstance] setMessageHistoryId:msg.messageDBId filetransferMimeType:info[@"mimeType"] filetransferSize:info[@"size"]];
                }
            }
        }
        
        //remove old db tables completely
        [[DataLayer sharedInstance] removeImageCacheTables];
        [[HelperTools defaultsDB] setBool:YES forKey:@"ImageCacheMigratedToFiletransferCache"];
        DDLogInfo(@"Migration done");
    }
}

#pragma mark - internal methods

+(NSString*) retrieveCacheFileForUrl:(NSString*) url andMimeType:(NSString*) mimeType
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

+(NSString*) calculateCacheFileForNewUrl:(NSString*) url andMimeType:(NSString*) mimeType
{
    //the cache filename consists of a hash of the upload url (in hex) followed of the file mimetype (also in hex) as file extension
    NSString* urlPart = [HelperTools hexadecimalString:[HelperTools sha256:[url dataUsingEncoding:NSUTF8StringEncoding]]];
    NSString* mimePart = [HelperTools hexadecimalString:[mimeType dataUsingEncoding:NSUTF8StringEncoding]];
    return [documentCache stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", urlPart, mimePart]];
}

+(NSString*) genCanonicalUrl:(NSString*) url
{
    NSURLComponents* urlComponents = [NSURLComponents componentsWithString:url];
    if(!urlComponents)
    {
        DDLogWarn(@"Failed to get url components, returning url possibly still including an urlfragment!");
        return url;
    }
    if([[urlComponents.scheme lowercaseString] isEqualToString:@"aesgcm"])
        urlComponents.scheme = @"https";
    urlComponents.fragment = @"";       //make sure we don't leak urlfragments to upload server
    return urlComponents.string;
}

+(NSString*) getMimeTypeOfOriginalFile:(NSString*) file
{
    CFStringRef UTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)[file pathExtension], NULL);
    NSString* mimeType = (__bridge_transfer NSString*)UTTypeCopyPreferredTagWithClass(UTI, kUTTagClassMIMEType);
    CFRelease(UTI);
    if(!mimeType)
        mimeType = @"application/octet-stream";
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
    DDLogDebug(@"Reading file data into NSData object");
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
        DDLogInfo(@"Encrypting file data before upload");
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
    
    //make sure we don't leak information about encrypted files
    if(encrypted)
        mimeType = @"application/octet-stream";
    DDLogDebug(@"Requesting file upload slot for mimeType %@", mimeType);
    [account requestHTTPSlotWithParams:@{
        kData:fileData,
        kFileName:userFacingFilename,
        kContentType:mimeType
    } andCompletion:^(NSString *url, NSError *error) {
        NSURLComponents* urlComponents = [NSURLComponents componentsWithString:url];
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
                                        [HelperTools hexadecimalString:[encryptedPayload.key subdataWithRange:NSMakeRange(0, 32)]]];
                                        //[HelperTools hexadecimalString:encryptedPayload.key]];
                url = urlComponents.string;
            }

            //move the tempfile to our cache location
            NSString* cacheFile = [self calculateCacheFileForNewUrl:url andMimeType:mimeType];
            DDLogInfo(@"Moving (possibly encrypted) file to our document cache at %@", cacheFile);
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
