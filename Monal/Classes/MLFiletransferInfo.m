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
+(NSString*) retrieveCacheFileForUrl:(NSString*) url andMimeType:(NSString*) mimeType;
@end

@interface MLFiletransferInfo ()

@property (nonatomic) NSNumber* historyId;
@property (nonatomic) NSString* mimeType;
@property (nonatomic) NSNumber* size;

@property (nonatomic) DownloadState downloadState;

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

    NSString* mimeType = data[@"mimeType"];
    NSNumber* size = data[@"size"];
    NSNumber* downloadState = data[@"downloadState"];
    MLAssert(mimeType != nil && size != nil && downloadState != nil, @"Notification without mimeType and/or size and/or downloadState");
    self.mimeType = mimeType;
    self.size = size;
    self.downloadState = downloadState.unsignedIntegerValue;
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
}

-(DownloadState) downloadState
{
    // return already cached value.
    if(_downloadState != DownloadStateUndefined)
        return _downloadState;

    DownloadState state;
    if(self.cacheFile)
        state = DownloadStateComplete;
    else if(self.size && self.mimeType && ![self.mimeType isEqualToString:@""])
        state = DownloadStateHeaders;
    else
        state = DownloadStateNone;

    self.downloadState = state;
    return _downloadState;
}

-(NSString*) url
{
    return self.message.messageText;
}

-(NSString*) filename
{
    NSURLComponents* urlComponents = [NSURLComponents componentsWithString:self.url];
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

-(NSString* _Nullable) cacheFile
{
    return [MLFiletransfer retrieveCacheFileForUrl:self.url andMimeType:(self.mimeType && ![self.mimeType isEqualToString:@""] ? self.mimeType : nil)];
}

-(NSString* _Nullable) cacheId
{
    return [self.cacheFile lastPathComponent];
}

-(UTType* _Nullable) typeHint
{
    if(self.mimeType == nil)
        return nil;

    UTType* type = [UTType typeWithMIMEType:self.mimeType];
    if(type != nil)
        return type;

    if([self.mimeType hasPrefix:@"image/"])
        return UTTypeImage;
    if([self.mimeType hasPrefix:@"audio/"])
        return UTTypeAudio;
    if([self.mimeType hasPrefix:@"video/"])
       return UTTypeMovie;
    return nil;
}

-(MLMessage*) message
{
    return [MLMessage createMessageFromHistoryID:self.historyId];
}

// Needed to not create a retain cycle between MLFiletransferInfo and MLMessage
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
