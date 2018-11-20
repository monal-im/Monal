//
//  MLBaseCell.m
//  Monal
//
//  Created by Anurodh Pokharel on 12/24/17.
//  Copyright © 2017 Monal.im. All rights reserved.
//

#import "MLBaseCell.h"

@implementation MLBaseCell

- (void)awakeFromNib {
    [super awakeFromNib];
    
    BOOL backgrounds = [[NSUserDefaults standardUserDefaults] boolForKey:@"ChatBackgrounds"];
    if(backgrounds) {
        self.name.textColor=[UIColor whiteColor];
        self.date.textColor=[UIColor whiteColor];
        self.messageStatus.textColor=[UIColor whiteColor];
    }
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}


-(void) updateCell
{
    self.retry.tintColor=[UIColor redColor]; // not needed once everything uses prototype
    if([self.parent respondsToSelector:@selector(retry:)]) {
        [self.retry addTarget:self.parent action:@selector(retry:) forControlEvents:UIControlEventTouchUpInside];
    }
    
    self.retry.tag= [self.messageHistoryId integerValue];
    
    if(self.deliveryFailed) {
        self.retry.hidden=NO;
    }
    else{
        self.retry.hidden=YES;
    }
}

@end
