//
//  MLProcessLock.m
//  monalxmpp
//
//  Created by Thilo Molitor on 26.07.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MLProcessLock.h"

@interface MLProcessLock()
{
    NSString* _processName;
}

@end

@implementation MLProcessLock

-(void) initWithProcessName:(NSString*) processName
{
    _processName = processName;
    
}

@end
