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
+(NSDictionary* _Nullable) getFileInfoForMessage:(MLMessage* _Nullable) msg;
+(void) deleteFileForMessage:(MLMessage* _Nullable) msg;
+(MLHandler*) prepareFileUpload:(NSURL*) fileUrl;
+(MLHandler*) prepareUIImageUpload:(UIImage*) image;
+(void) uploadFile:(NSURL*) fileUrl onAccount:(xmpp*) account withEncryption:(BOOL) encrypted andCompletion:(void (^)(NSString* _Nullable url, NSString* _Nullable mimeType, NSNumber* _Nullable size, NSError* _Nullable error)) completion;
+(void) uploadUIImage:(UIImage*) image onAccount:(xmpp*) account withEncryption:(BOOL) encrypted andCompletion:(void (^)(NSString* _Nullable url, NSString* _Nullable mimeType, NSNumber* _Nullable size, NSError* _Nullable error)) completion;
+(void) hardlinkFileForMessage:(MLMessage*) msg;
+(BOOL) isFileforHistoryIdInTransfer:(NSNumber*) historyId;
+(NSString*) getMimeTypeOfOriginalFile:(NSString*) file;

@end

NS_ASSUME_NONNULL_END
