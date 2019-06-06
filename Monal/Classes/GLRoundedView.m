//
//  GLRoundedView.m
//  Monal
//
//  Created by Anurodh Pokharel on 11/7/17.
//  Copyright © 2017 Anurodh Pokharel. All rights reserved.
//

#import "GLRoundedView.h"

@implementation GLRoundedView

-(id) initWithCoder:(NSCoder *)aDecoder
{
    self=[super initWithCoder:aDecoder];
    if(self){
        [self update];
    }
    return self;
}

-(id) initWithFrame:(CGRect)frame
{
    self=[super initWithFrame:frame];
    if(self){
        [self update];
    }
    return self;
}

- (void) prepareForInterfaceBuilder
{
    [super prepareForInterfaceBuilder];
    [self update];
}

-(void) update {
    self.layer.cornerRadius=20;
  //  self.backgroundColor=[UIColor whiteColor];
}


@end
