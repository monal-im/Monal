//
//  MLFiletransferInfo.h
//  monalxmpp
//
//  Created by lissine on 16/12/2025.
//  Copyright © 2025 monal-im.org. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class MLMessage;

typedef NS_ENUM(NSUInteger, DownloadState) {
    DownloadStateUndefined, // equivalent of nil
    DownloadStateNone,
    DownloadStateHeaders,
    DownloadStateComplete,
};

@interface MLFiletransferInfo : NSObject

@property (nonatomic, readonly) NSNumber* historyId;
@property (nonatomic, readonly) NSString* _Nullable mimeType;
@property (nonatomic, readonly) NSNumber* _Nullable size;

@property (nonatomic, readonly) DownloadState downloadState;
@property (nonatomic, readonly) double mediaDuration;
@property (nonatomic, readonly) NSURL* _Nullable thumbnailURL;

@property (nonatomic, readonly) NSString* url;
@property (nonatomic, readonly) NSString* filename;
@property (nonatomic, readonly) NSString* fileExtension;
@property (nonatomic, readonly) NSString* _Nullable cacheFile;
@property (nonatomic, readonly) NSString* _Nullable cacheId;
@property (nonatomic, readonly) UTType* _Nullable typeHint;

@property (nonatomic, readonly) BOOL isImage;
@property (nonatomic, readonly) BOOL isAudio;
@property (nonatomic, readonly) BOOL isVideo;
@property (nonatomic, readonly) BOOL isPDF;

@property (nonatomic, readonly) MLMessage* message;

+(MLFiletransferInfo*) createFiletransferInfoForMessage:(MLMessage*) message;

@end

NS_ASSUME_NONNULL_END
