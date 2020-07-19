//
//  MLContactDetailHeader.m
//  Monal
//
//  Created by Anurodh Pokharel on 12/29/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import "MLContactDetailHeader.h"

@implementation MLContactDetailHeader

- (void)awakeFromNib {
    [super awakeFromNib];
   
    self.buddyIconView.layer.cornerRadius =  self.buddyIconView.frame.size.height / 2;
    self.buddyIconView.layer.borderColor = [UIColor whiteColor].CGColor;
    self.buddyIconView.layer.borderWidth = 2.0f;
    self.buddyIconView.clipsToBounds = YES;
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

@end
