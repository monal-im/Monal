//
//  UIView.m
//  SworIM
//
//  Created by Anurodh Pokharel on 1/16/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "CustomCell.h"


// actual implementation of subclass
@implementation CustomCell


@synthesize statusOrb; 


- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated
{
	
	[super setHighlighted:highlighted animated:animated];

	

	
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated
{
  //  [super setSelected:selected animated:selected];
   // [self applyLabelDropShadow:!selected];
}



- (void)layoutSubviews
{
    
    [super layoutSubviews];  //The default implementation of the layoutSubviews
    
    CGRect orbRectangle = CGRectMake(51-13+8,(self.frame.size.height/2) -7,15,15);
	statusOrb = [[UIImageView alloc] initWithFrame:orbRectangle];
    [self.contentView addSubview: statusOrb ];
    
    
    CGRect textLabelFrame = self.textLabel.frame;
    textLabelFrame.origin.x=51+13;
    textLabelFrame.size.width = self.frame.size.width-51-13-35-45;
    self.textLabel.frame = textLabelFrame;
    
    
    CGRect detailLabelFrame = self.detailTextLabel.frame;
    detailLabelFrame.origin.x=51+13;
    detailLabelFrame.size.width = self.frame.size.width-51-13-35-45;
    self.detailTextLabel.frame = detailLabelFrame;
    
    
}


@end
