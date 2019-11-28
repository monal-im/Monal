//
//  MLMessage.m
//  Monal
//
//  Created by Anurodh Pokharel on 11/27/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import "MLMessage.h"

@implementation MLMessage

-(BOOL) shouldForceRefresh
{
    if(self.delayTimeStamp!=nil) return YES;
    else return NO;
}

@end
