//
//  MLFiletransferInfo.m
//  monalxmpp
//
//  Created by lissine on 16/12/2025.
//  Copyright © 2025 monal-im.org. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <monalxmpp/HelperTools.h>
#import <monalxmpp/DataLayer.h>
#import <monalxmpp/MLMessage.h>
#import <monalxmpp/MLFiletransfer.h>
#import <monalxmpp/MLFiletransferInfo.h>
#import <monalxmpp/MLImageManager.h>

@import UniformTypeIdentifiers;

static NSMutableDictionary* _singletonCache;

@interface MLFiletransfer ()
+(NSString*) retrieveCacheFilePathForUrl:(NSString*) url andMimeType:(NSString*) mimeType;
@end

@interface MLFiletransferInfo ()

@property (nonatomic) NSNumber* historyId;
@property (nonatomic) NSString* mimeType;
@property (nonatomic) NSNumber* size;

@property (nonatomic) DownloadState downloadState;
@property (nonatomic) double mediaDuration;
@property (atomic) BOOL isComputingMediaDuration;
@property (nonatomic) NSURL* thumbnailURL;
@property (atomic) BOOL isGeneratingThumbnail;

@end

@implementation MLFiletransferInfo

+(void) initialize
{
    _singletonCache = [NSMutableDictionary new];
}

+(MLFiletransferInfo*) createFiletransferInfoForMessage:(MLMessage*) message
{
    MLAssert([message.messageType isEqualToString:kMessageTypeFiletransfer], @"message not of type filetransfer!", (@{@"message": message}));

    NSNumber* cacheKey = message.messageDBId;
    MLAssert(cacheKey != nil, @"A filetransfer message can't have a nil historyId!");

    MLFiletransferInfo* fileInfo = nil;
    @synchronized(_singletonCache) {
        if(_singletonCache[cacheKey] != nil)
        {
            MLFiletransferInfo* obj = ((WeakContainer*)_singletonCache[cacheKey]).obj;
            DDLogDebug(@"Singleton cache for filetransferInfo filled: %@, entry: %@", cacheKey, obj);
            if(obj != nil)
                return obj;
            else
                [_singletonCache removeObjectForKey:cacheKey];
        }
        NSDictionary* dic = [[DataLayer sharedInstance] getFiletransferInfoForHistoryId:message.messageDBId];
        // dic shouldn't be nil unless there's an implementation error.
        MLAssert(dic != nil, @"A row in the filetransfer_info db table MUST exist for a filetransfer message!");
        fileInfo = [MLFiletransferInfo new];
        fileInfo.historyId = [dic objectForKey:@"message_history_id"];
        fileInfo.mimeType = [dic objectForKey:@"mime_type"];
        fileInfo.size = [dic objectForKey:@"size"];
        _singletonCache[cacheKey] = [[WeakContainer alloc] initWithObj:fileInfo];
    }
    return fileInfo;
}

-(instancetype) init
{
    self = [super init];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleFiletransferUpdate:) name:kMonalMessageFiletransferUpdateNotice object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleMessageDeletion:) name:kMonalDeletedMessageNotice object:nil];
    return self;
}

-(void) handleFiletransferUpdate:(NSNotification*) notification
{
    NSDictionary* data = notification.userInfo;
    MLMessage* message = data[@"message"];
    MLAssert(message != nil, @"Notification without message");
    if(self.historyId.integerValue != message.messageDBId.integerValue)
        return;         //ignore filetransfer updates of other messages

    [self refresh];
}

-(void) handleMessageDeletion:(NSNotification*) notification
{
    NSDictionary* data = notification.userInfo;
    MLAssert(data[@"historyId"] != nil, @"kMonalDeletedMessageNotice without historyId!");
    if(self.historyId.integerValue != [data[@"historyId"] integerValue])
        return;         //ignore deletions of other messages

    self.mimeType = @"";
    self.size = @0;
    self.downloadState = DownloadStateUndefined;
    self.mediaDuration = 0.0;
    self.thumbnailURL = nil;
}

-(void) refresh
{
    NSDictionary* dic = [[DataLayer sharedInstance] getFiletransferInfoForHistoryId:self.historyId];
    if(dic == nil)
        DDLogError(@"A row in the filetransfer_info db table SHOULD exist for a filetransferInfo object!");

    updateIfIdNotEqual(self.mimeType, [dic objectForKey:@"mime_type"]);
    updateIfIdNotEqual(self.size, [dic objectForKey:@"size"]);
    // Reset the cached value of downloadState. This will cause it to be recalculated on next read access
    // (which will happen soon due to the KVO notification emitted by calling the setter)
    self.downloadState = DownloadStateUndefined;
}

-(DownloadState) downloadState
{
    // return already cached value.
    if(_downloadState != DownloadStateUndefined)
        return _downloadState;

    DownloadState state;
    if(self.cacheFilePath)
        state = DownloadStateComplete;
    else if(self.size && self.mimeType && ![self.mimeType isEqualToString:@""])
        state = DownloadStateHeaders;
    else
        state = DownloadStateNone;

    self.downloadState = state;
    return _downloadState;
}

-(double) mediaDuration {
    // return already cached value.
    if(_mediaDuration != 0.0)
        return _mediaDuration;

    // Compute the duration, but try to ensure that only one thread is doing so
    // Also prevent further retries in the case of an error
    // Note that isComputingMediaDuration is not thread safe
    if(!self.isComputingMediaDuration) {
        self.isComputingMediaDuration = YES;
        [HelperTools computeMediaDurationFromFile:self.cacheFilePath havingMimeType:self.mimeType andFileExtension:self.fileExtension]
        .then(^(NSNumber* duration) {
            // The following instruction triggers a ChatView update
            self.mediaDuration = duration.doubleValue;
            self.isComputingMediaDuration = NO;
        }).catch(^(NSError* error) {
            DDLogError(@"Could not compute media duration: %@", error);
        });
    }

    // return _mediaDuration (which contains 0.0) while the computation happens in a background thread
    return _mediaDuration;
}

-(NSURL*) thumbnailURL {
    // return thumbnail cached in memory.
    if(_thumbnailURL != nil)
        return _thumbnailURL;

    // return thumbnail cached on disk
    NSURL* url = [[MLImageManager sharedInstance] getThumbnailURLOfMessage:self.message];
    if(url != nil)
    {
        self.thumbnailURL = url;
        return url;
    }

    // Generate the thumbnail now, but try to ensure that only one thread is doing the generation
    // Also, prevent retries in the case of an error (to avoid repeated failures)
    // Note that isGeneratingThumbnail is not thread safe.
    if(!self.isGeneratingThumbnail)
    {
        self.isGeneratingThumbnail = YES;
        [HelperTools generateVideoThumbnailFromFile:self.cacheFilePath havingMimeType:self.mimeType andFileExtension:self.fileExtension]
        .then(^(UIImage* image) {
            NSData* imageData = UIImagePNGRepresentation(image);
            // The following instruction triggers a ChatView update
            self.thumbnailURL = [[MLImageManager sharedInstance] setThumbnailOfMessage:self.message withData:imageData];
            self.isGeneratingThumbnail = NO;
        }).catch(^(NSError* error) {
            DDLogError(@"Could not create video thumbnail: %@", error);
        });
    }

    // return _thumbnailURL (which is nil) while thumbnail generation happens in a background thread
    return _thumbnailURL;
}

// downloadURL doesn't emit KVO notifications if it changes (it's not possible to declare
// it as depending on messageText, because that's only accessible through a computed property).
// downloadURL is not supposed to change. But if it does, those that depend on it won't get notified.
-(NSString*) downloadURL
{
    return self.message.messageText;
}

-(NSString*) filename
{
    NSURLComponents* urlComponents = [NSURLComponents componentsWithString:self.downloadURL];
    if(urlComponents != nil && urlComponents.path)
        return [urlComponents.path lastPathComponent];
    else
        //dummy filename
        return [NSString stringWithFormat:@"%@.bin", [[NSUUID UUID] UUIDString]];
}

-(NSString*) fileExtension
{
    return [self.filename pathExtension];
}

-(NSString* _Nullable) cacheFilePath
{
    return [MLFiletransfer retrieveCacheFilePathForUrl:self.downloadURL andMimeType:(self.mimeType && ![self.mimeType isEqualToString:@""] ? self.mimeType : nil)];
}

+(NSSet*) keyPathsForValuesAffectingCacheFilePath
{
    return [NSSet setWithObjects:@"mimeType", nil];
}

-(NSString* _Nullable) cacheId
{
    return [self.cacheFilePath lastPathComponent];
}

+(NSSet*) keyPathsForValuesAffectingCacheId
{
    return [NSSet setWithObjects:@"mimeType", nil];
}

-(UTType* _Nullable) utType
{
    if(self.mimeType == nil)
        return nil;

    UTType* type = [UTType typeWithMIMEType:self.mimeType];
    if(type != nil)
        return type;

    if(self.isImage)
        return UTTypeImage;
    if(self.isAudio)
        return UTTypeAudio;
    if(self.isVideo)
       return UTTypeMovie;
    return nil;
}

+(NSSet*) keyPathsForValuesAffectingUtType
{
    return [NSSet setWithObjects:@"mimeType", nil];
}

-(BOOL) isImage
{
    return [self.mimeType hasPrefix:@"image/"];
}

+(NSSet*) keyPathsForValuesAffectingIsImage
{
    return [NSSet setWithObjects:@"mimeType", nil];
}

-(BOOL) isAudio
{
    return [self.mimeType hasPrefix:@"audio/"];
}

+(NSSet*) keyPathsForValuesAffectingIsAudio
{
    return [NSSet setWithObjects:@"mimeType", nil];
}

-(BOOL) isVideo
{
    return [self.mimeType hasPrefix:@"video/"];
}

+(NSSet*) keyPathsForValuesAffectingIsVideo
{
    return [NSSet setWithObjects:@"mimeType", nil];
}

-(BOOL) isPDF
{
    return [self.mimeType isEqualToString:@"application/pdf"];
}

+(NSSet*) keyPathsForValuesAffectingIsPDF
{
    return [NSSet setWithObjects:@"mimeType", nil];
}

// Needed to not create a retain cycle between MLFiletransferInfo and MLMessage
-(MLMessage*) message
{
    return [MLMessage createMessageFromHistoryID:self.historyId];
}

-(NSString*) id
{
    return [NSString stringWithFormat:@"%@", self.historyId];
}

-(NSString*) description
{
    return [NSString stringWithFormat:@"FiletransferInfo of historyId %@ with {mimeType: %@, size: %@, downloadState: %lu} --> (%p)",
        self.historyId,
        self.mimeType,
        self.size,
        self.downloadState,
        self
    ];
}

@end
