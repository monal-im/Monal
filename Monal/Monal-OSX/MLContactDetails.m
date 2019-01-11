//
//  MLContactDetails.m
//  Monal
//
//  Created by Anurodh Pokharel on 8/13/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import "MLContactDetails.h"
#import "MLImageManager.h"
#import "DataLayer.h"
#import "MLXMPPManager.h"
@import QuartzCore; 

@interface MLContactDetails ()

@end

@implementation MLContactDetails

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
}

-(void) viewWillAppear
{
    [super viewWillAppear];
     [[MLXMPPManager sharedInstance] getVCard:_contact];
    self.buddyName.stringValue =[_contact objectForKey:@"buddy_name"];
    
    self.buddyMessage.stringValue=[_contact objectForKey:@"status"];
    if([self.buddyMessage.stringValue isEqualToString:@"(null)"])  self.buddyMessage.stringValue=@"";
    
    self.buddyStatus.stringValue=[_contact objectForKey:@"state"];
    if([self.buddyStatus.stringValue isEqualToString:@"(null)"])  self.buddyStatus.stringValue=@"";
    
    self.fullName.stringValue=[_contact objectForKey:@"full_name"];
    if([self.fullName.stringValue isEqualToString:@"(null)"])  self.fullName.stringValue=@"";
    
    self.buddyIconView.wantsLayer=YES;
    self.buddyIconView.layer.cornerRadius= self.buddyIconView.frame.size.height/2;
    self.buddyIconView.layer.borderColor=[NSColor whiteColor].CGColor;
    self.buddyIconView.layer.borderWidth=2.0f;
    
     NSString* accountNo=[NSString stringWithFormat:@"%@", [_contact objectForKey:@"account_id"]];
//    [[DataLayer sharedInstance] contactForUsername:[_contact objectForKey:@"buddy_name"] forAccount:accountNo withCompletion:^(NSArray *result) {
//
//     self.subscription.stringValue=[_contact objectForKey:@"full_name"];
//        if([self.subscription.stringValue isEqualToString:@"(null)"])  self.subscription.stringValue=@"";
//
//
//    }];
    
    NSArray* parts= [self.buddyName.stringValue componentsSeparatedByString:@"@"];
    if([parts count]>1)
    {
        NSString* domain= [parts objectAtIndex:1];
        if([domain isEqualToString:@"gmail.com"])
        {
            //gtalk
            _protocolImage.image=[NSImage imageNamed:@"GTalk"];
        }
        else
            
            //xmpp
            _protocolImage.image=[NSImage imageNamed:@"XMPP"];
        
    }
 ;
  [[MLImageManager sharedInstance] getIconForContact:[_contact objectForKey:@"buddy_name"] andAccount:accountNo withCompletion:^(NSImage *contactImage) {
        self.buddyIconView.image=contactImage;
  }];
  
    
    NSArray* resources= [[DataLayer sharedInstance] resourcesForContact:[_contact objectForKey:@"buddy_name"]];
    self.resourcesTextView.string=@"";
    for(NSDictionary* row in resources)
    {
        self.resourcesTextView.string=[NSString stringWithFormat:@"%@\n%@\n",self.resourcesTextView.string, [row objectForKey:@"resource"]];

    }

}

@end
