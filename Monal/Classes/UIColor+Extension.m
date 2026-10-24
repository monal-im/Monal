//
//  UIColor+Extension.m
//  Monal
//
//  Created by Thilo Molitor on 04.11.21.
//  Copyright © 2021 Monal.im. All rights reserved.
//

#import <monalxmpp/UIColor+Extension.h>

@implementation UIColor (Extension)
-(BOOL) isLightColor
{
    CGFloat colorBrightness = 0;
    CGColorSpaceRef colorSpace = CGColorGetColorSpace(self.CGColor);
    CGColorSpaceModel colorSpaceModel = CGColorSpaceGetModel(colorSpace);
    if(colorSpaceModel == kCGColorSpaceModelRGB)
    {
        const CGFloat* componentColors = CGColorGetComponents(self.CGColor);
        colorBrightness = ((componentColors[0] * 299) + (componentColors[1] * 587) + (componentColors[2] * 114)) / 1000;
    }
    else
        [self getWhite:&colorBrightness alpha:0];
    return (colorBrightness >= .5f);
}
@end
