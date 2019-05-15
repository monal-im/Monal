//
//  MLChatImageCell.m
//  Monal
//
//  Created by Anurodh Pokharel on 12/24/17.
//  Copyright © 2017 Monal.im. All rights reserved.
//

#import "MLChatImageCell.h"
#import "MLImageManager.h"
@import QuartzCore; 

@implementation MLChatImageCell

- (void)awakeFromNib {
    [super awakeFromNib];
    // Initialization code
    self.thumbnailImage.layer.cornerRadius=15.0f;
    self.thumbnailImage.layer.masksToBounds=YES;
}

-(void) loadImageWithCompletion:(void (^)(void))completion
{
    if(self.link && self.thumbnailImage.image==nil && !self.loading)
    {
        self.loading=YES;
        [[MLImageManager sharedInstance] imageForAttachmentLink:self.link withCompletion:^(NSData * _Nullable data) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if(!data) {
                    self.thumbnailImage.image=nil;
                }
               else if(!self.thumbnailImage.image) {
                    UIImage *image= [UIImage imageWithData:data];
                    [self.thumbnailImage setImage:image];
                    if (image.size.height>image.size.width) {
                        self.imageHeight.constant = 360;
                    }
                }
                self.loading=NO;
                if(completion) completion();
            });
        }];
    }
    else  {
        
    }
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

-(BOOL) canPerformAction:(SEL)action withSender:(id)sender
{
    return (action == @selector(copy:)) ;
}

-(void) copy:(id)sender {
    UIPasteboard *pboard = [UIPasteboard generalPasteboard];
    pboard.image = self.thumbnailImage.image; 
}

-(void)prepareForReuse{
    [super prepareForReuse];
    self.imageHeight.constant=200;
}


@end
