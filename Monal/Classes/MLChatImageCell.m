//
//  MLChatImageCell.m
//  Monal
//
//  Created by Anurodh Pokharel on 12/24/17.
//  Copyright © 2017 Monal.im. All rights reserved.
//

#import "MLChatImageCell.h"
#import "UIImageView+WebCache.h"

@implementation MLChatImageCell

- (void)awakeFromNib {
    [super awakeFromNib];
    // Initialization code
}

-(void) loadImage
{
    if(self.link)
    {
        [self.thumbnailImage sd_setImageWithURL:[NSURL URLWithString:self.link] completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, NSURL *imageURL) {
            if(error)
            {
                self.thumbnailImage.image=nil;
            }
            
        }];
    }
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

@end
