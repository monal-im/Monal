//
//  MLMAMPref.m
//  Monal-OSX
//
//  Created by Anurodh Pokharel on 4/22/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import "MLMAMPref.h"

@implementation MLMAMPref

-(void) viewDidLoad
{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updatePrefs:) name:kMLMAMPref object:nil];
}

-(void) viewWillAppear
{
    [self.xmppAccount getMAMPrefs];
}

-(void) updatePrefs:(NSNotification *) notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
       
        NSDictionary *dic= (NSDictionary *) notification.object;
        NSString* val =[dic objectForKey:@"mamPref"];
        [self displayPrefWithValue:val];
        
    });
}

-(void) displayPrefWithValue:(NSString *) value
{
    for (NSView* subview in self.view.subviews)
    {
        if(subview.tag==1 && [value isEqualToString:@"always"])
        {
              NSButton *radio = (NSButton*) subview;
            [radio setState:NSControlStateValueOn];
        }
        
        if(subview.tag==2 && [value isEqualToString:@"never"])
        {
            NSButton *radio = (NSButton*) subview;
           [radio setState:NSControlStateValueOn];
        }
        
        if(subview.tag==3 && [value isEqualToString:@"roster"])
        {
            NSButton *radio = (NSButton*) subview;
            [radio setState:NSControlStateValueOn];
        }
    }
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
