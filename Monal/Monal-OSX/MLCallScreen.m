//
//  MLCallScreen.m
//  Monal-OSX
//
//  Created by Anurodh Pokharel on 1/8/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import "MLCallScreen.h"
#import "MLXMPPManager.h"

@interface MLCallScreen ()

@end

@implementation MLCallScreen

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
}


-(void) viewWillAppear
{
    self.callButton.enabled=YES;
    if(self.contact) {
        NSString *contactName = self.contact.contactJid;
     
        if(!contactName) {
            contactName = @"No Contact Selected";
            self.callButton.enabled=NO;
        }
        
        self.contactName.stringValue=contactName;
    }
}

-(IBAction)hangup:(id)sender
{
    [[MLXMPPManager sharedInstance] hangupContact:self.contact];
    self.callButton.enabled=NO; 
    
}


@end
