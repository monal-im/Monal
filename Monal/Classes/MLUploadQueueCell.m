//
//  MLUploadQueueCell.m
//  Monal
//
//  Created by Jan on 13.04.21.
//  Copyright © 2021 Monal.im. All rights reserved.
//

#import "MLUploadQueueCell.h"

@implementation MLUploadQueueCell

-(IBAction) closeButtonAction
{
    [self.uploadQueueDelegate notifyUploadQueueRemoval:self.index];
}

-(void) initCellWithPreviewImage:(UIImage* _Nullable) previewImage filename:(NSString* _Nullable) filename index:(NSUInteger) idx
{
    if(previewImage == nil)
        previewImage = [UIImage systemImageNamed:@"doc"];
    self.previewImage.image = previewImage;
    self.fileName.text = filename;
    self.index = idx;
    if(filename == nil)
        self.fileName.hidden = YES;
    else
        self.fileName.hidden = NO;
}

@end
