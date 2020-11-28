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

@interface MLFiletransfer : NSObject

+(void) checkMimeTypeAndSizeForHistoryID:(NSNumber*) historyId;
+(void) downloadFileForHistoryID:(NSNumber*) historyId;
+(NSDictionary* _Nullable) getFileInfoForMessage:(MLMessage* _Nullable) msg;
+(void) deleteFileForMessage:(MLMessage* _Nullable) msg;
+(void) uploadFile:(NSURL*) fileUrl onAccount:(xmpp*) account withEncryption:(BOOL) encrypt andCompletion:(void (^)(NSString* _Nullable url, NSString* _Nullable mimeType, NSNumber* _Nullable size, NSError* _Nullable)) completion;
+(void) uploadUIImage:(UIImage*) image onAccount:(xmpp*) account withEncryption:(BOOL) encrypt andCompletion:(void (^)(NSString* _Nullable url, NSString* _Nullable mimeType, NSNumber* _Nullable size, NSError* _Nullable)) completion;

@end

NS_ASSUME_NONNULL_END
