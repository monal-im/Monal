//
//  MLUploadQueueImageCell.m
//  Monal
//
//  Created by Jan on 02.04.21.
//  Copyright © 2021 Monal.im. All rights reserved.
//

#import "MLUploadQueueImageCell.h"
#import "HelperTools.h"

@implementation MLUploadQueueImageCell

-(void) initCellWithImage:(UIImage*) image index:(NSUInteger)idx
{
    self.imagePreview.image = image;
    self.index = idx;
}

@end
