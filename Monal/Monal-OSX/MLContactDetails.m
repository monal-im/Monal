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
#import "MLKeyViewController.h"
#import "MLResourcesViewController.h"
@import QuartzCore; 

@interface MLContactDetails ()
@property (nonatomic, strong) xmpp* xmppAccount;
@end

@implementation MLContactDetails

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
}

-(void) viewWillAppear
{
    [super viewWillAppear];
     [[MLXMPPManager sharedInstance] getVCard:self.contact];
    self.buddyName.stringValue =self.contact.contactJid;
 
    
    self.buddyMessage.stringValue= self.contact.statusMessage?self.contact.statusMessage:@"";
    if([self.buddyMessage.stringValue isEqualToString:@"(null)"])  self.buddyMessage.stringValue=@"";
    
    self.buddyStatus.stringValue=     self.contact.state;
    if([self.buddyStatus.stringValue isEqualToString:@"(null)"])  self.buddyStatus.stringValue=@"";
    
    self.fullName.stringValue=self.contact.contactDisplayName;
    if([self.fullName.stringValue isEqualToString:@"(null)"])  self.fullName.stringValue=@"";
    
    self.buddyIconView.wantsLayer=YES;
    self.buddyIconView.layer.cornerRadius= self.buddyIconView.frame.size.height/2;
    self.buddyIconView.layer.borderColor=[NSColor whiteColor].CGColor;
    self.buddyIconView.layer.borderWidth=2.0f;
    
     NSString* accountNo=self.contact.accountId;
//    [[DataLayer sharedInstance] contactForUsername: self.contact.contactJid forAccount:accountNo withCompletion:^(NSArray *result) {
//
//     self.subscription.stringValue=[self.contact objectForKey:@"full_name"];
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
 
#ifndef DISABLE_OMEMO
    self.xmppAccount = [[MLXMPPManager sharedInstance] getConnectedAccountForID:accountNo];
    [self.xmppAccount queryOMEMODevicesFrom: self.contact.contactJid];
#endif
    
  [[MLImageManager sharedInstance] getIconForContact: self.contact.contactJid andAccount:accountNo withCompletion:^(NSImage *contactImage) {
        self.buddyIconView.image=contactImage;
  }];
  
    
    NSArray* resources= [[DataLayer sharedInstance] resourcesForContact: self.contact.contactJid];
    self.resourcesTextView.string=@"";
    for(NSDictionary* row in resources)
    {
        self.resourcesTextView.string=[NSString stringWithFormat:@"%@\n%@\n",self.resourcesTextView.string, [row objectForKey:@"resource"]];

    }

}

-(void) prepareForSegue:(NSStoryboardSegue *)segue sender:(id)sender
{
    if([segue.identifier isEqualToString:@"showKeys"])
    {
        MLKeyViewController *keys = (MLKeyViewController *)segue.destinationController;
        keys.contact= self.contact;
    }
    else if([segue.identifier isEqualToString:@"showResources"])
    {
          MLResourcesViewController *resources = (MLResourcesViewController *)segue.destinationController;
          resources.contact= self.contact;
    }
}

@end
