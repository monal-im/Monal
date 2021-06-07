//
//  MLUploadQueueAddCell.m
//  Monal
//
//  Created by Jan on 08.06.21.
//  Copyright © 2021 Monal.im. All rights reserved.
//

#import "MLUploadQueueAddCell.h"

@implementation MLUploadQueueAddCell

-(void) awakeFromNib
{
    [super awakeFromNib];
    if(@available(iOS 13.0, *)) {} else
    {
        UIImage* addButtonImage = [UIImage imageNamed:@"907-plus-rounded-square"];
        assert(self.addButton != nil);
        assert(addButtonImage != nil);
        [self.addButton setBackgroundImage:addButtonImage forState:UIControlStateNormal];
    }
}

@end
