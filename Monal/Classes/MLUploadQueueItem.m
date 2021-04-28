//
//  MLUploadQueueItem.m
//  Monal
//
//  Created by Jan on 16.04.21.
//  Copyright © 2021 Monal.im. All rights reserved.
//

#import "MLUploadQueueItem.h"
#import "MLConstants.h"
#import "MLDefinitions.h"

@interface MLUploadQueueItem()
{
    MLUploadQueueItemType _type;
}
@property (nonatomic, strong) UIImage* image;
@property (nonatomic, strong) NSURL* url;
@end

@implementation MLUploadQueueItem
-(MLUploadQueueItemType) getType
{
    return _type;
}

-(UIImage*) getImage
{
    assert(_type == UPLOAD_QUEUE_TYPE_RAW_IMAGE || _type == UPLOAD_QUEUE_TYPE_IMAGE_WITH_URL);
    assert(self.image != nil);
    return self.image;
}

-(NSURL*) getURL
{
    assert(_type == UPLOAD_QUEUE_TYPE_URL || _type == UPLOAD_QUEUE_TYPE_IMAGE_WITH_URL);
    assert(self.url != nil);
    return self.url;
}

-(id) initWithImage:(UIImage*) image {
    assert(image != nil);
    assert(self = [super init]);
    _type = UPLOAD_QUEUE_TYPE_RAW_IMAGE;
    self.image = image;
    self.url = nil;
    return self;
}

-(id) initWithImage:(UIImage*) image imageUrl:(NSURL *)url
{
    assert(image != nil);
    assert(url != nil);
    assert(self = [super init]);
    _type = UPLOAD_QUEUE_TYPE_IMAGE_WITH_URL;
    self.image = image;
    self.url = url;
    return self;
}

-(id) initWithURL:(NSURL*) url
{
    assert(url != nil);
    assert(self = [super init]);
    // MLUploadQueueItem* item = [MLUploadQueueItem alloc];
    _type = UPLOAD_QUEUE_TYPE_URL;
    self.url = url;
    self.image = nil;
    return self;
}

-(BOOL) isEqual:(id) other {
    if([self getType] != [other getType]) {
        return false;
    }
    switch([self getType]) {
        case UPLOAD_QUEUE_TYPE_RAW_IMAGE:
            // return false; // Can't detect duplicates, so skip this
            // FIXME Based on documentation, this could work in some cases (but won't in most):
            return [[self getImage] isEqual:[other getImage]];
        case UPLOAD_QUEUE_TYPE_IMAGE_WITH_URL: // Images are also compared via their URL
        case UPLOAD_QUEUE_TYPE_URL:
            return [[self getURL].absoluteString isEqualToString:[other getURL].absoluteString];
        default:
            unreachable();
            return false;
    }
}

@end
