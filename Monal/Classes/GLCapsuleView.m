//
//  GLCapsuleView.m
//  Monal
//
//  Created by Anurodh Pokharel on 11/7/17.
//  Copyright © 2017 Anurodh Pokharel. All rights reserved.
//

#import "GLCapsuleView.h"
#import "UIColor+Theme.h"


@implementation GLCapsuleView

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
    self.layer.borderColor=[UIColor monalGreen].CGColor;
    //self.backgroundColor=[UIColor whiteColor];
    self.layer.borderWidth=1.0;
}

@end
