//
//  GLTintButton.m
//  Goldilocks
//
//  Created by Anurodh Pokharel on 11/7/17.
//  Copyright © 2017 Anurodh Pokharel. All rights reserved.
//

#import "GLTintButton.h"
#import "UIColor+Theme.h"

@implementation GLTintButton

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
    self.layer.cornerRadius=self.frame.size.height/2;
    self.backgroundColor=[UIColor monalGreen];
    [self setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.layer.borderWidth=0.0;
}


@end
