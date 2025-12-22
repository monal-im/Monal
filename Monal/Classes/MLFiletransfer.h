//
//  MLFiletransfer.h
//  monalxmpp
//
//  Created by Thilo Molitor on 12.11.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class MLMessage;
@class xmpp;

@interface MLFiletransfer : NSObject<NSURLSessionDownloadDelegate>
@property (class, readonly) BOOL isIdle;

+(BOOL) isIdle;
+(void) doStartupCleanup;
+(void) checkMimeTypeAndSizeForHistoryID:(NSNumber*) historyId;
+(void) downloadFileForHistoryID:(NSNumber*) historyId;
+(void) deleteFileForMessage:(MLMessage* _Nullable) msg;
+(MLHandler*) prepareDataUpload:(NSData*) data;
+(MLHandler*) prepareDataUpload:(NSData*) data withFileExtension:(NSString*) fileExtension;
+(MLHandler*) prepareFileUpload:(NSURL*) fileUrl;
+(MLHandler*) prepareUIImageUpload:(UIImage*) image;
+(AnyPromise*) uploadFile:(NSURL*) fileUrl onAccount:(xmpp*) account withEncryption:(BOOL) encrypted;
+(AnyPromise*) uploadUIImage:(UIImage*) image onAccount:(xmpp*) account withEncryption:(BOOL) encrypted;
+(void) hardlinkFileForMessage:(MLMessage*) msg;
+(BOOL) isFileForHistoryIdInTransfer:(NSNumber*) historyId;
+(NSString*) getMimeTypeOfOriginalFile:(NSString*) file;

@end

NS_ASSUME_NONNULL_END
