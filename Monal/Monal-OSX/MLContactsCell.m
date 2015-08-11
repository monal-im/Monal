//
//  MLContactsCell.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/28/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import "MLContactsCell.h"

@implementation MLContactsCell

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    
    // Drawing code here.
}

-(void) setOrb
{
    switch (self.state) {
        case kStatusAway:
        {
            self.statusOrb.image=[NSImage imageNamed:@"away"];
           // self.imageView.alpha=1.0f;
            break;
        }
        case kStatusOnline:
        {
            self.statusOrb.image=[NSImage imageNamed:@"available"];
            //self.imageView.alpha=1.0f;
            break;
        }
        case kStatusOffline:
        {
            self.statusOrb.image=[NSImage imageNamed:@"offline"];
           // self.imageView.alpha=0.5f;
            break;
        }
            
        default:
            break;
    }
}

@end
