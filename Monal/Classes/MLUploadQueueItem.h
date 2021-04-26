//
//  MLUploadQueueItem.h
//  Monal
//
//  Created by Jan on 16.04.21.
//  Copyright © 2021 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, MLUploadQueueItemType) {
    UPLOAD_QUEUE_TYPE_RAW_IMAGE, // Used by Image Picker < iOS 14
    UPLOAD_QUEUE_TYPE_IMAGE_WITH_URL, // Used by Image Picker >= iOS 14 - can detect duplicates
    UPLOAD_QUEUE_TYPE_URL
};

@interface MLUploadQueueItem : NSObject
-(MLUploadQueueItemType) getType;
-(UIImage*) getImage;
-(NSURL*) getURL;

-(id) initWithImage:(UIImage*) image;
-(id) initWithImage:(UIImage*) image imageUrl:(NSURL*) url; // optional URL param to detect duplicates. Does not work with Image Picker < iOS 14.
-(id) initWithURL:(NSURL*) url;

-(BOOL) isEqual:(id) other;
@end

NS_ASSUME_NONNULL_END
