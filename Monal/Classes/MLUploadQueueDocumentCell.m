//
//  MLUploadQueueDocumentCell.m
//  Monal
//
//  Created by Jan on 13.04.21.
//  Copyright © 2021 Monal.im. All rights reserved.
//

#import "MLUploadQueueDocumentCell.h"
#import "MLConstants.h"

@implementation MLUploadQueueDocumentCell

-(UIImage*) genPreviewImage:(NSURL*) url
{
    // iCloud approach
    NSDictionary* thumbnails = nil;
    NSError* error = nil;
    BOOL success = [url getPromisedItemResourceValue:&thumbnails
                                              forKey:NSURLThumbnailDictionaryKey
                                               error:&error];
    if (success == YES && thumbnails.count > 0)
    {
        NSArray<UIImage*>* values = [thumbnails allValues];
        return values.firstObject;
    }
    else
    {
        DDLogVerbose(@"Extracting thumbnail from document failed: %@", error.localizedDescription);
        UIImage* result = [[UIImage alloc] initWithData:[NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:&error]]; // FIXME options
        if(result != nil) {
            return result;
        }
        DDLogVerbose(@"Thumbnail generation not successful - reverting to generic image for file");
        UIDocumentInteractionController* imgCtrl = [UIDocumentInteractionController interactionControllerWithURL:url]; // Memory leak? I want C++ back :/
        if(imgCtrl != nil && imgCtrl.icons.count > 0)
        {
            return imgCtrl.icons.firstObject;
        }
        else
        {
            if (@available(iOS 13.0, *)) {
                return [UIImage systemImageNamed:@"doc"];
            } else {
                return nil;
            }
        }
    }
}

-(void) initCellWithURL:(NSURL*) url index:(NSUInteger)idx
{
    self.fileName.text = url.lastPathComponent;
    self.previewImage.image = [self genPreviewImage:url];
    self.index = idx;
}
@end
