//
//  MLActiveChatCell.m
//  Monal
//
//  Created by Anurodh Pokharel on 9/12/12.
//
//

#import "MLActiveChatCell.h"

@implementation MLActiveChatCell
// actual implementation of subclass




- (void)setSelected:(BOOL)selected animated:(BOOL)animated
{
    //  [super setSelected:selected animated:selected];
    // [self applyLabelDropShadow:!selected];
}

- (void)layoutSubviews
{

    [super layoutSubviews];  //The default implementation of the layoutSubviews
    
    CGRect textLabelFrame = self.textLabel.frame;
    textLabelFrame.size.width = 187;
    self.textLabel.frame = textLabelFrame;
}



@end
