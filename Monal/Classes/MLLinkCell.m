//
//  MLLinkCell.m
//  Monal
//
//  Created by Anurodh Pokharel on 10/29/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import "MLLinkCell.h"
#import "UIImageView+WebCache.h"

@implementation MLLinkCell

- (void)awakeFromNib {
    [super awakeFromNib];
    // Initialization code
    self.bubbleView.layer.cornerRadius=16.0f;
    self.bubbleView.clipsToBounds=YES;
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

-(void) loadImageWithCompletion:(void (^)(void))completion
{
    if(self.imageUrl)
    {
        [self.previewImage sd_setImageWithURL:[NSURL URLWithString:self.imageUrl] completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, NSURL *imageURL) {
            if(error)
            {
                self.previewImage.image=nil;
            }
            else  {
                
            }
            
        }];
    }
}

@end
