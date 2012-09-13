//
//  UIView.h
//  SworIM
//
//  Created by Anurodh Pokharel on 1/16/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "DDBadgeViewCell.h"



@interface  CustomCell:DDBadgeViewCell
{
   
    UIImageView* statusOrb;
}
- (void)drawRect:(CGRect)rect; 


@property (nonatomic) UIImageView* statusOrb;

@end
