//
//  MLUploadQueueBaseCell.m
//  Monal
//
//  Created by Jan on 15.04.21.
//  Copyright © 2021 Monal.im. All rights reserved.
//

#import "MLUploadQueueBaseCell.h"

@implementation MLUploadQueueBaseCell

-(IBAction) closeButtonAction
{
    [self.uploadQueueDelegate notifyUploadQueueRemoval:self.index];
}

@end
