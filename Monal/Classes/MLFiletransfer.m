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
#import "DataLayer.h"
#import "MLEncryptedPayload.h"
#import "xmpp.h"
#import "AESGcm.h"
#import "MLXMPPManager.h"
#import "MLNotificationQueue.h"

@import MobileCoreServices;

static NSFileManager* _fileManager;
static NSString* _documentCacheDir;
static NSMutableSet* _currentlyTransfering;

NSMutableDictionary<NSString*, NSNumber*>* _expectedDownloadSizes;

@implementation MLFiletransfer

+(void) initialize
{
    NSError* error;
    _fileManager = [NSFileManager defaultManager];
    _documentCacheDir = [[[_fileManager containerURLForSecurityApplicationGroupIdentifier:kAppGroup] path] stringByAppendingPathComponent:@"documentCache"];
    
    [_fileManager createDirectoryAtURL:[NSURL fileURLWithPath:_documentCacheDir] withIntermediateDirectories:YES attributes:nil error:&error];
    if(error)
            @throw [NSException exceptionWithName:@"NSError" reason:[NSString stringWithFormat:@"%@", error] userInfo:@{@"error": error}];
    [HelperTools configureFileProtectionFor:_documentCacheDir];
    
    _currentlyTransfering = [[NSMutableSet alloc] init];
    _expectedDownloadSizes = [[NSMutableDictionary alloc] init];
}

+(BOOL) isIdle
{
    @synchronized(_currentlyTransfering)
    {
        return [_currentlyTransfering count] == 0;
    }
}

+(void) checkMimeTypeAndSizeForHistoryID:(NSNumber*) historyId
{
    NSString* url;
    MLMessage* msg = [[DataLayer sharedInstance] messageForHistoryID:historyId];
    if(!msg)
    {
        DDLogError(@"historyId %@ does not yield an MLMessage object, aborting", historyId);
        return;
    }
    url = [self genCanonicalUrl:msg.messageText];
    @synchronized(_expectedDownloadSizes)
    {
        if(_expectedDownloadSizes[url] == NULL)
        {
            _expectedDownloadSizes[url] = msg.filetransferSize;
        }
    }
    //make sure we don't check or download this twice
    @synchronized(_currentlyTransfering)
    {
        if([_currentlyTransfering containsObject:historyId])
        {
            DDLogDebug(@"Already checking/downloading this content, ignoring");
            return;
        }
        [_currentlyTransfering addObject:historyId];
    }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        DDLogInfo(@"Requesting mime-type and size for historyID %@ from http server", historyId);
        NSMutableURLRequest* request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:url]];
        request.HTTPMethod = @"HEAD";
        request.cachePolicy = NSURLRequestReturnCacheDataElseLoad;

        NSURLSession* session = [NSURLSession sharedSession];
        [[session dataTaskWithRequest:request completionHandler:^(NSData* _Nullable data __unused, NSURLResponse* _Nullable response, NSError* _Nullable error __unused) {
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

            //send out update notification (and update used MLMessage object directly instead of reloading it from db after updating the db)
            msg.filetransferMimeType = mimeType;
            msg.filetransferSize = contentLength;
            xmpp* account = [[MLXMPPManager sharedInstance] getConnectedAccountForID:msg.accountId];
            [[MLNotificationQueue currentQueue] postNotificationName:kMonalMessageFiletransferUpdateNotice object:account userInfo:@{@"message": msg}];
            
            //try to autodownload if sizes match
            long autodownloadMaxSize = [[HelperTools defaultsDB] integerForKey:@"AutodownloadFiletransfersWifiMaxSize"];
            if([[MLXMPPManager sharedInstance] onMobile])
               autodownloadMaxSize = [[HelperTools defaultsDB] integerForKey:@"AutodownloadFiletransfersMobileMaxSize"];
            if(
                [[HelperTools defaultsDB] boolForKey:@"AutodownloadFiletransfers"] &&
                [contentLength intValue] >= 0 &&        //-1 means we don't know the size --> don't autodownload files of unknown sizes
                [contentLength integerValue] <= autodownloadMaxSize
            )
            {
                DDLogInfo(@"Autodownloading file");
                [self downloadFileForHistoryID:historyId andForceDownload:YES];     //ignore already existing _currentlyTransfering entry leftover from this header check
            }
            else
            {
                //check done, remove from "currently checking/downloading list"
                [self markAsComplete:historyId];
            }
                
        }] resume];
    });
}

+(void) downloadFileForHistoryID:(NSNumber*) historyId
{
    [self downloadFileForHistoryID:historyId andForceDownload:NO];
}

+(void) downloadFileForHistoryID:(NSNumber*) historyId andForceDownload:(BOOL) forceDownload
{
    MLMessage* msg = [[DataLayer sharedInstance] messageForHistoryID:historyId];
    if(!msg)
    {
        DDLogError(@"historyId %@ does not yield an MLMessage object, aborting", historyId);
        return;
    }
    //make sure we don't check or download this twice (but only do this if the download is not forced anyway)
    @synchronized(_currentlyTransfering)
    {
        if(!forceDownload && [_currentlyTransfering containsObject:historyId])
        {
            DDLogDebug(@"Already checking/downloading this content, ignoring");
            return;
        }
        [_currentlyTransfering addObject:historyId];
    }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        DDLogInfo(@"Downloading file for historyID %@", historyId);
        NSString* url = [self genCanonicalUrl:msg.messageText];
        NSURLComponents* urlComponents = [NSURLComponents componentsWithString:msg.messageText];
        if(!urlComponents)
        {
            DDLogError(@"url components decoding failed");
            [self setErrorType:NSLocalizedString(@"Download error", @"") andErrorText:NSLocalizedString(@"Failed to decode download link", @"") forMessageId:msg.messageId];
            [self markAsComplete:historyId];
            return;
        }
        
        NSURLSession* session = [NSURLSession sharedSession];
        // set app defined description for download size checks
        [session setSessionDescription:url];
        NSURLSessionDownloadTask* task = [session downloadTaskWithURL:[NSURL URLWithString:url] completionHandler:^(NSURL* _Nullable location, NSURLResponse* _Nullable response, NSError* _Nullable error) {
            if(error)
            {
                DDLogError(@"File download failed: %@", error);
                [self setErrorType:NSLocalizedString(@"Download error", @"") andErrorText:NSLocalizedString(@"Failed to download file", @"") forMessageId:msg.messageId];
                [self markAsComplete:historyId];
                return;
            }
            
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
                    [self markAsComplete:historyId];
                    return;
                }
                int ivLength = 24;
                //format is iv+32byte key
                NSData* key = [HelperTools dataWithHexString:[urlComponents.fragment substringWithRange:NSMakeRange(ivLength, 64)]];
                NSData* iv = [HelperTools dataWithHexString:[urlComponents.fragment substringToIndex:ivLength]];
                
                //decrypt data with given key and iv
                NSData* encryptedData = [NSData dataWithContentsOfURL:location];
                if(encryptedData && encryptedData.length > 0 && key && key.length == 32 && iv && iv.length == 12)
                {
                    NSData* decryptedData = [AESGcm decrypt:encryptedData withKey:key andIv:iv withAuth:nil];
                    [decryptedData writeToFile:cacheFile options:NSDataWritingAtomic error:&error];
                    if(error)
                    {
                        DDLogError(@"File download failed: %@", error);
                        [self setErrorType:NSLocalizedString(@"Download error", @"") andErrorText:NSLocalizedString(@"Failed to write decrypted download into cache directory", @"") forMessageId:msg.messageId];
                        [self markAsComplete:historyId];
                        return;
                    }
                    [HelperTools configureFileProtectionFor:cacheFile];
                }
                else
                {
                    DDLogError(@"Failed to decrypt file (iv, key, data length checks failed)");
                    [self setErrorType:NSLocalizedString(@"Download error", @"") andErrorText:NSLocalizedString(@"Failed to decrypt filetransfer", @"") forMessageId:msg.messageId];
                    [self markAsComplete:historyId];
                    return;
                }
            }
            else        //cleartext filetransfer
            {
                //copy file to our document cache
                DDLogInfo(@"Copying downloaded file to document cache at %@", cacheFile);
                [_fileManager moveItemAtPath:[location path] toPath:cacheFile error:&error];
                if(error)
                {
                    DDLogError(@"File download failed: %@", error);
                    [self setErrorType:NSLocalizedString(@"Download error", @"") andErrorText:NSLocalizedString(@"Failed to copy downloaded file into cache directory", @"") forMessageId:msg.messageId];
                    [self markAsComplete:historyId];
                    return;
                }
                [HelperTools configureFileProtectionFor:cacheFile];
            }
            
            //update MLMessage object with mime type and size
            NSNumber* filetransferSize = @([[_fileManager attributesOfItemAtPath:cacheFile error:nil] fileSize]);
            msg.filetransferMimeType = mimeType;
            msg.filetransferSize = filetransferSize;
            
            //hardlink cache file if possible
            [self hardlinkFileForMessage:msg];
            
            DDLogDebug(@"Updating db and sending out kMonalMessageFiletransferUpdateNotice");
            //update db with content type and size
            [[DataLayer sharedInstance] setMessageHistoryId:historyId filetransferMimeType:mimeType filetransferSize:filetransferSize];
            //send out update notification (using our directly update MLMessage object instead of reloading it from db after updating the db)
            xmpp* account = [[MLXMPPManager sharedInstance] getConnectedAccountForID:msg.accountId];
            [[MLNotificationQueue currentQueue] postNotificationName:kMonalMessageFiletransferUpdateNotice object:account userInfo:@{@"message": msg}];
            
            //download done, remove from "currently checking/downloading list"
            [self markAsComplete:historyId];
        }];
        [task resume];
    });
}

-(void) URLSession:(NSURLSession*) session downloadTask:(NSURLSessionDownloadTask*) downloadTask didWriteData:(int64_t) bytesWritten totalBytesWritten:(int64_t) totalBytesWritten totalBytesExpectedToWrite:(int64_t) totalBytesExpectedToWrite
{
    @synchronized(_expectedDownloadSizes)
    {
        NSNumber* expectedSize = _expectedDownloadSizes[session.sessionDescription];
        if(expectedSize == NULL) {
            [downloadTask cancel];
        } else if(totalBytesWritten >= expectedSize.intValue + 1024 * 1000 * 1000) {
            [downloadTask cancel];
        } else {
            // everything is ok
        }
    }
}

-(void) URLSession:(nonnull NSURLSession*) session downloadTask:(nonnull NSURLSessionDownloadTask*) downloadTask didFinishDownloadingToURL:(nonnull NSURL*) location
{
    @synchronized(_expectedDownloadSizes)
    {
        [_expectedDownloadSizes removeObjectForKey:session.sessionDescription];
    }
}


$$class_handler(handleHardlinking, $$ID(xmpp*, account), $$ID(NSString*, cacheFile), $$ID((NSArray<NSString*>*), hardlinkPathComponents), $$BOOL(direct))
    NSError* error;    
    
    if([HelperTools isAppExtension])
    {
        DDLogWarn(@"NOT hardlinking cache file at '%@' into documents directory at '%@': we STILL are in the appex, rescheduling this to next account connect", cacheFile, [hardlinkPathComponents componentsJoinedByString:@"/"]);
        //the reconnect handler framework will add $ID(account) to the callerArgs, no need to add an accountNo etc. here
        [account addReconnectionHandler:$newHandler(self, handleHardlinking,
            $ID(cacheFile),
            $ID(hardlinkPathComponents),
            $BOOL(direct, NO)
        )];
        return;
    }
    
    if(![_fileManager fileExistsAtPath:cacheFile])
    {
        DDLogError(@"Source file does not exists?!");
#ifdef DEBUG
        @throw [NSException exceptionWithName:@"ERROR_WHILE_HARDLINKING_FILE_NOT_PRESENT" reason:@"Could not hardlink cacheFile, file not present!" userInfo:@{@"cacheFile": cacheFile}];
#endif
        return;
    }
    
    //copy file created in appex to a temporary location and then rename it to be at the original location
    //this allows hardlinking later on because now the mainapp owns that file while it had only read/write access before
    if(!direct)
    {
        NSString* cacheFileTMP = [NSString stringWithFormat:@"%@.tmp", cacheFile];
        DDLogInfo(@"Copying appex-created cache file '%@' to '%@' before deleting old file and renaming our copy...", cacheFile, cacheFileTMP);
        [_fileManager copyItemAtPath:cacheFile toPath:cacheFileTMP error:&error];
        if(error)
        {
            DDLogError(@"Could not copy cache file to tmp file: %@", error);
#ifdef DEBUG
            @throw [NSException exceptionWithName:@"ERROR_WHILE_COPYING_CACHEFILE" reason:@"Could not copy cacheFile!" userInfo:@{
                @"cacheFile": cacheFile,
                @"cacheFileTMP": cacheFileTMP
            }];
#endif
            return;
        }
        
        [_fileManager removeItemAtPath:cacheFile error:&error];
        if(error)
        {
            DDLogError(@"Could not delete original cache file: %@", error);
#ifdef DEBUG
            @throw [NSException exceptionWithName:@"ERROR_WHILE_DELETING_CACHEFILE" reason:@"Could not delete cacheFile!" userInfo:@{
                @"cacheFile": cacheFile
            }];
#endif
            return;
        }
        
        [_fileManager moveItemAtPath:cacheFileTMP toPath:cacheFile error:&error];
        if(error)
        {
            DDLogError(@"Could not rename tmp file to cache file: %@", error);
#ifdef DEBUG
            @throw [NSException exceptionWithName:@"ERROR_WHILE_RENAMING_CACHEFILE" reason:@"Could not rename cacheFileTMP to cacheFile!" userInfo:@{
                @"cacheFile": cacheFile,
                @"cacheFileTMP": cacheFileTMP
            }];
#endif
            return;
        }
    }
    
    NSURL* hardLink = [[_fileManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    for(NSString* pathComponent in hardlinkPathComponents)
        hardLink = [hardLink URLByAppendingPathComponent:pathComponent];
    
    DDLogInfo(@"Hardlinking cache file at '%@' into documents directory at '%@'...", cacheFile, hardLink);
    if(![_fileManager fileExistsAtPath:[hardLink.URLByDeletingLastPathComponent path]])
    {
        DDLogVerbose(@"Creating hardlinking dir struct at '%@'...", hardLink.URLByDeletingLastPathComponent); 
        [_fileManager createDirectoryAtURL:hardLink.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:@{NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication} error:&error];
        if(error)
            DDLogWarn(@"Ignoring error creating hardlinking dir struct at '%@': %@", hardLink, error);
        else
            [HelperTools configureFileProtection:NSFileProtectionCompleteUntilFirstUserAuthentication forFile:[hardLink path]];
    }
    
    //don't throw any error if the file aready exists, because it could be a rare collision (we only use 16 bit random numbers to keep the file prefix short)
    if([_fileManager fileExistsAtPath:[hardLink path]])
        DDLogWarn(@"Not hardlinking file '%@' to '%@': file already exists (maybe a rare collision?)...", cacheFile, hardLink);
    else
    {
        DDLogVerbose(@"Hardlinking cache file '%@' to '%@'...", cacheFile, hardLink);
        [_fileManager linkItemAtPath:cacheFile toPath:[hardLink path] error:&error];
        if(error)
        {
            DDLogError(@"Error creating hardlink: %@", error);
            @throw [NSException exceptionWithName:@"ERROR_WHILE_HARDLINKING_FILE" reason:[NSString stringWithFormat:@"%@", error] userInfo:@{@"error": error}];
        }
    }
$$

+(void) hardlinkFileForMessage:(MLMessage*) msg
{
    NSDictionary* fileInfo = [self getFileInfoForMessage:msg];
    xmpp* account = [[MLXMPPManager sharedInstance] getConnectedAccountForID:msg.accountId];
    
    NSString* groupDisplayName = nil;
    NSString* fromDisplayName = nil;
    MLContact* contact = [MLContact createContactFromJid:msg.buddyName andAccountNo:msg.accountId];
    if(msg.isMuc)
    {
        groupDisplayName = contact.contactDisplayName;
        fromDisplayName = msg.contactDisplayName;
    }
    else
        fromDisplayName = contact.contactDisplayName;
    
    //this resembles to /Files/<account_jid>/<contact_name> for 1:1 contacts and /Files/<account_jid>/<group_name>/<contact_in_group_name> for mucs (channels AND groups)
    NSMutableArray* hardlinkPathComponents = [[NSMutableArray alloc] init];
    [hardlinkPathComponents addObject:account.connectionProperties.identity.jid];
    if(groupDisplayName != nil)
        [hardlinkPathComponents addObject:groupDisplayName];
    [hardlinkPathComponents addObject:fromDisplayName];
    
    //put incoming and outgoing files in different directories
    if(msg.inbound)
    {
        //put every mime-type in its own type directory
        if([fileInfo[@"mimeType"] hasPrefix:@"image/"])
            [hardlinkPathComponents addObject:NSLocalizedString(@"Received Images", @"directory for downloaded images")];
        else if([fileInfo[@"mimeType"] hasPrefix:@"video/"])
            [hardlinkPathComponents addObject:NSLocalizedString(@"Received Videos", @"directory for downloaded videos")];
        else if([fileInfo[@"mimeType"] hasPrefix:@"audio/"])
            [hardlinkPathComponents addObject:NSLocalizedString(@"Received Audios", @"directory for downloaded audios")];
        else
            [hardlinkPathComponents addObject:NSLocalizedString(@"Received Files", @"directory for downloaded files")];
    }
    else
    {
        //put every mime-type in its own type directory
        if([fileInfo[@"mimeType"] hasPrefix:@"image/"])
            [hardlinkPathComponents addObject:NSLocalizedString(@"Sent Images", @"directory for downloaded images")];
        else if([fileInfo[@"mimeType"] hasPrefix:@"video/"])
            [hardlinkPathComponents addObject:NSLocalizedString(@"Sent Videos", @"directory for downloaded videos")];
        else if([fileInfo[@"mimeType"] hasPrefix:@"audio/"])
            [hardlinkPathComponents addObject:NSLocalizedString(@"Sent Audios", @"directory for downloaded audios")];
        else
            [hardlinkPathComponents addObject:NSLocalizedString(@"Sent Files", @"directory for downloaded files")];
    }
    
    u_int16_t i=(u_int16_t)arc4random();
    NSString* randomID = [HelperTools hexadecimalString:[NSData dataWithBytes: &i length: sizeof(i)]];
    [hardlinkPathComponents addObject:[NSString stringWithFormat:@"%@_%@", randomID, fileInfo[@"filename"]]];
    
    MLHandler* handler = $newHandler(self, handleHardlinking, $ID(cacheFile, fileInfo[@"cacheFile"]), $ID(hardlinkPathComponents), $BOOL(direct, NO));
    if([HelperTools isAppExtension])
    {
        DDLogWarn(@"NOT hardlinking cache file at '%@' into documents directory at %@: we are in the appex, rescheduling this to next account connect", fileInfo[@"cacheFile"], [hardlinkPathComponents componentsJoinedByString:@"/"]);
        [account addReconnectionHandler:handler];       //the reconnect handler framework will add $ID(account) to the callerArgs, no need to add an accountNo etc. here
    }
    else
        $call(handler, $ID(account), $BOOL(direct, YES));       //no reconnect handler framework used, explicitly bind $ID(account) via callerArgs
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
    
    //return every information we have
    if(!cacheFile)
    {
        //if we have mimeype and size the http head request was already done, else we did not even do a head request
        if(msg.filetransferMimeType != nil && msg.filetransferSize != nil)
            return @{
                @"url": msg.messageText,
                @"filename": filename,
                @"needsDownloading": @YES,
                @"mimeType": msg.filetransferMimeType,
                @"size": msg.filetransferSize,
            };
        else
            return @{
                @"url": msg.messageText,
                @"filename": filename,
                @"needsDownloading": @YES,
            };
    }
    return @{
        @"url": msg.messageText,
        @"filename": filename,
        @"needsDownloading": @NO,
        @"mimeType": [self getMimeTypeOfCacheFile:cacheFile],
        @"size": @([[_fileManager attributesOfItemAtPath:cacheFile error:nil] fileSize]),
        @"cacheId": [cacheFile lastPathComponent],
        @"cacheFile": cacheFile,
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
        [_fileManager removeItemAtPath:info[@"cacheFile"] error:nil];
    }
}

+(MLHandler*) prepareFileUpload:(NSURL*) fileUrl
{
    DDLogInfo(@"Preparing for upload of file stored at %@", [fileUrl path]);
    
    //copy file to our document cache (temporary filename because the upload url is unknown yet)
    NSString* tempname = [NSString stringWithFormat:@"%@.tmp", [[NSUUID UUID] UUIDString]];
    NSError* error;
    NSString* file = [_documentCacheDir stringByAppendingPathComponent:tempname];
    DDLogDebug(@"Tempstoring file at %@", file);
    [_fileManager copyItemAtPath:[fileUrl path] toPath:file error:&error];
    if(error)
    {
        [_fileManager removeItemAtPath:file error:nil];      //remove temporary file
        DDLogError(@"File upload failed: %@", error);
        return $newHandler(self, errorCompletion, $ID(error));
    }
    [HelperTools configureFileProtectionFor:file];
    
    return $newHandler(self, internalTmpFileUploadHandler,
        $ID(file),
        $ID(userFacingFilename, [fileUrl lastPathComponent]),
        $ID(mimeType, [self getMimeTypeOfOriginalFile:[fileUrl path]])
    );
}

+(MLHandler*) prepareUIImageUpload:(UIImage*) image
{
    DDLogInfo(@"Preparing for upload of image from UIImage object");
    double imageQuality = [[HelperTools defaultsDB] doubleForKey:@"ImageUploadQuality"];
    
    //copy file to our document cache (temporary filename because the upload url is unknown yet)
    NSString* tempname = [NSString stringWithFormat:@"%@.tmp", [[NSUUID UUID] UUIDString]];
    NSError* error;
    NSString* file = [_documentCacheDir stringByAppendingPathComponent:tempname];
    DDLogDebug(@"Tempstoring jpeg encoded file having quality %f at %@", imageQuality, file);
    NSData* imageData = UIImageJPEGRepresentation(image, imageQuality);
    [imageData writeToFile:file options:NSDataWritingAtomic error:&error];
    if(error)
    {
        [_fileManager removeItemAtPath:file error:nil];      //remove temporary file
        DDLogError(@"File upload failed: %@", error);
        return $newHandler(self, errorCompletion, $ID(error));
    }
    [HelperTools configureFileProtectionFor:file];
    
    return $newHandler(self, internalTmpFileUploadHandler,
        $ID(file),
        $ID(userFacingFilename, ([NSString stringWithFormat:@"%@.jpg", [[NSUUID UUID] UUIDString]])),
        $ID(mimeType, @"image/jpeg")
    );
}

//proxy to allow calling the completion with a (possibly) serialized error
$$class_handler(errorCompletion, $$ID(NSError*, error), $$ID(monal_upload_completion_t, completion))
    completion(nil, nil, nil, error);
$$

+(void) uploadFile:(NSURL*) fileUrl onAccount:(xmpp*) account withEncryption:(BOOL) encrypted andCompletion:(monal_upload_completion_t) completion
{
    DDLogInfo(@"Uploading file stored at %@", [fileUrl path]);
    //directly call internal file upload handler returned as MLHandler and bind our (non serializable) completion block to it
    $call([self prepareFileUpload:fileUrl], $ID(account), $BOOL(encrypted), $ID(completion));
}

+(void) uploadUIImage:(UIImage*) image onAccount:(xmpp*) account withEncryption:(BOOL) encrypted andCompletion:(monal_upload_completion_t) completion
{
    DDLogInfo(@"Uploading image from UIImage object");
    //directly call internal file upload handler returned as MLHandler and bind our (non serializable) completion block to it
    $call([self prepareUIImageUpload:image], $ID(account), $BOOL(encrypted), $ID(completion));
}

+(void) doStartupCleanup
{
    //delete leftover tmp files
    NSArray* directoryContents = [_fileManager contentsOfDirectoryAtPath:_documentCacheDir error:nil];
    NSPredicate* filter = [NSPredicate predicateWithFormat:@"self ENDSWITH '.tmp'"];
    for(NSString* file in [directoryContents filteredArrayUsingPredicate:filter])
    {
        DDLogInfo(@"Deleting leftover tmp file at %@", [_documentCacheDir stringByAppendingPathComponent:file]);
        [_fileManager removeItemAtPath:[_documentCacheDir stringByAppendingPathComponent:file] error:nil];
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
            if([_fileManager fileExistsAtPath:oldFile])
            {
                [_fileManager copyItemAtPath:oldFile toPath:newFile error:nil];
                [HelperTools configureFileProtectionFor:newFile];
                [_fileManager removeItemAtPath:oldFile error:nil];
            }
            else
                DDLogWarn(@"Old file not existing --> not moving file, but still updating db entries");
            
            //update every history_db entry with new filetransfer metadata
            //(this will flip the message type to kMessageTypeFiletransfer and set correct mimeType and size values)
            NSArray* messageList = [[DataLayer sharedInstance] getAllMessagesForFiletransferUrl:img[@"url"]];
            if(![messageList count])
            {
                DDLogWarn(@"No messages in history db having this url, deleting file completely");
                [_fileManager removeItemAtPath:newFile error:nil];
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
        NSString* cacheFile = [_documentCacheDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", urlPart, mimePart]];
        
        //file having the supplied mimeType exists
        if([_fileManager fileExistsAtPath:cacheFile])
            return cacheFile;
    }
    
    //check for files having a different mime type but the same base url
    NSArray* directoryContents = [_fileManager contentsOfDirectoryAtPath:_documentCacheDir error:nil];
    NSPredicate* filter = [NSPredicate predicateWithFormat:[NSString stringWithFormat:@"self BEGINSWITH '%@.'", urlPart]];
    for(NSString* file in [directoryContents filteredArrayUsingPredicate:filter])
        return [_documentCacheDir stringByAppendingPathComponent:file];
    
    //nothing found
    return nil;
}

+(NSString*) calculateCacheFileForNewUrl:(NSString*) url andMimeType:(NSString*) mimeType
{
    //the cache filename consists of a hash of the upload url (in hex) followed of the file mimetype (also in hex) as file extension
    NSString* urlPart = [HelperTools hexadecimalString:[HelperTools sha256:[url dataUsingEncoding:NSUTF8StringEncoding]]];
    NSString* mimePart = [HelperTools hexadecimalString:[mimeType dataUsingEncoding:NSUTF8StringEncoding]];
    return [_documentCacheDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", urlPart, mimePart]];
}

+(NSString*) genCanonicalUrl:(NSString*) url
{
    NSURLComponents* urlComponents = [NSURLComponents componentsWithString:url];
    if(!urlComponents)
    {
        DDLogWarn(@"Failed to get url components, returning empty url!");
        return @"";
    }
    if([[urlComponents.scheme lowercaseString] isEqualToString:@"aesgcm"])
        urlComponents.scheme = @"https";
    if(![[urlComponents.scheme lowercaseString] isEqualToString:@"https"])
    {
        DDLogWarn(@"Failed to get url components, returning empty url!");
        return @"";
    }
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
    [[MLNotificationQueue currentQueue] postNotificationName:kMonalMessageErrorNotice object:nil userInfo:@{
        @"MessageID": messageId,
        @"errorType": errorType,
        @"errorReason": errorText
    }];
}

$$class_handler(internalTmpFileUploadHandler, $$ID(NSString*, file), $$ID(NSString*, userFacingFilename), $$ID(NSString*, mimeType), $$ID(xmpp*, account), $$BOOL(encrypted), $$ID(monal_upload_completion_t, completion))
    NSError* error;
    
    //make sure we don't upload the same tmpfile twice (should never happen anyways)
    @synchronized(_currentlyTransfering)
    {
        if([_currentlyTransfering containsObject:file])
        {
            error = [NSError errorWithDomain:@"MonalError" code:0 userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"Already uploading this content, ignoring", @"")}];
            DDLogError(@"Already uploading this content, ignoring %@", file);
            [_fileManager removeItemAtPath:file error:nil];      //remove temporary file
            return completion(nil, nil, nil, error);
        }
        [_currentlyTransfering addObject:file];
    }
    
    //TODO: allow real file based transfers instead of NSData based transfers
    DDLogDebug(@"Reading file data into NSData object");
    NSData* fileData = [[NSData alloc] initWithContentsOfFile:file options:0 error:&error];
    if(error)
    {
        [_fileManager removeItemAtPath:file error:nil];      //remove temporary file
        [self markAsComplete:file];
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
            [_fileManager removeItemAtPath:file error:nil];      //remove temporary file
            [self markAsComplete:file];
            DDLogError(@"File upload failed: %@", error);
            return completion(nil, nil, nil, error);
        }
    }
    
    //make sure we don't leak information about encrypted files
    NSString* sendMimeType = mimeType;
    if(encrypted)
        sendMimeType = @"application/octet-stream";
    
    DDLogDebug(@"Requesting file upload slot for mimeType %@", sendMimeType);
    [account requestHTTPSlotWithParams:@{
        @"data":fileData,
        @"fileName":userFacingFilename,
        @"contentType":sendMimeType
    } andCompletion:^(NSString *url, NSError *error) {
        if(error)
        {
            [_fileManager removeItemAtPath:file error:nil];      //remove temporary file
            [self markAsComplete:file];
            DDLogError(@"File upload failed: %@", error);
            return completion(nil, nil, nil, error);
        }
        
        NSURLComponents* urlComponents = [NSURLComponents componentsWithString:url];
        if(url && urlComponents)
        {
            //build aesgcm url containing "aesgcm" url-scheme and IV and AES-key in urlfragment
            if(encrypted)
            {
                urlComponents.scheme = @"aesgcm";
                urlComponents.fragment = [NSString stringWithFormat:@"%@%@",
                                        [HelperTools hexadecimalString:encryptedPayload.iv],
                                        //extract real aes key without authtag (32 bytes = 256bit) (conversations compatibility)
                                        [HelperTools hexadecimalString:[encryptedPayload.key subdataWithRange:NSMakeRange(0, 32)]]];
                url = urlComponents.string;
            }

            //move the tempfile to our cache location
            NSString* cacheFile = [self calculateCacheFileForNewUrl:url andMimeType:mimeType];
            DDLogInfo(@"Moving (possibly encrypted) file to our document cache at %@", cacheFile);
            [_fileManager moveItemAtPath:file toPath:cacheFile error:&error];
            if(error)
            {
                NSError* error = [NSError errorWithDomain:@"MonalError" code:0 userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"Failed to uploaded file to file cache directory", @"")}];
                [_fileManager removeItemAtPath:file error:nil];      //remove temporary file
                [self markAsComplete:file];
                DDLogError(@"File upload failed: %@", error);
                return completion(nil, nil, nil, error);
            }
            [HelperTools configureFileProtectionFor:cacheFile];
            
            [self markAsComplete:file];
            DDLogInfo(@"URL for download: %@", url);
            return completion(url, mimeType, [NSNumber numberWithInteger:fileData.length], nil);
        }
        else
        {
            NSError* error = [NSError errorWithDomain:@"MonalError" code:0 userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"Failed to parse URL returned by HTTP upload server", @"")}];
            [_fileManager removeItemAtPath:file error:nil];      //remove temporary file
            [self markAsComplete:file];
            DDLogError(@"File upload failed: %@", error);
            return completion(nil, nil, nil, error);
        }
    }];
$$

+(void) markAsComplete:(id) obj
{
    @synchronized(_currentlyTransfering)
    {
        [_currentlyTransfering removeObject:obj];
    }
    if(self.isIdle)
        //don't queue this notification because it should be handled immediately
        [[NSNotificationCenter defaultCenter] postNotificationName:kMonalFiletransfersIdle object:self];
}

+(BOOL) isFileforHistoryIdInTransfer:(NSNumber*) historyId
{
    if([_currentlyTransfering containsObject:historyId])
    {
        return YES;
    }
    return NO;
}
@end
