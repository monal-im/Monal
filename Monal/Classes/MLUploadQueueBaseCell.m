//
//  MLUploadQueueBaseCell.m
//  Monal
//
//  Created by Jan on 15.04.21.
//  Copyright © 2021 Monal.im. All rights reserved.
//

#import "MLUploadQueueBaseCell.h"

@implementation MLUploadQueueBaseCell

-(void) awakeFromNib
{
    [super awakeFromNib];
    if(@available(iOS 13.0, *)) {} else
    {
        UIImage* closeButtonImage = [UIImage imageNamed:@"away"];
        assert(self.closeButton != nil);
        assert(closeButtonImage != nil);
        [self.closeButton setImage:closeButtonImage forState:UIControlStateNormal];
    }
}

-(IBAction) closeButtonAction
{
    [self.uploadQueueDelegate notifyUploadQueueRemoval:self.index];
}

@end
