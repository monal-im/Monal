//
//  MLMAMPref.m
//  Monal-OSX
//
//  Created by Anurodh Pokharel on 4/22/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import "MLMAMPref.h"

@implementation MLMAMPref

-(void) viewWillAppear
{
    [self.xmppAccount getMAMPrefs];
}

-(IBAction)changePref:(id)sender
{
    NSButton *radio = (NSButton*) sender;
    switch(radio.tag)
    {
        case 1:{
            [self.xmppAccount setMAMPrefs:@"always"];
            break;
        }
        case 2:{
            [self.xmppAccount setMAMPrefs:@"never"];
            break;
        }
        case 3:{
            [self.xmppAccount setMAMPrefs:@"roster"];
            break;
        }
            
    }
}


@end
