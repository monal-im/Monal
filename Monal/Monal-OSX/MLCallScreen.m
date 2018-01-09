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
    self.contactName.stringValue= [self.contact objectForKey:@"user"];
    }
}

-(IBAction)hangup:(id)sender
{
    [[MLXMPPManager sharedInstance] hangupContact:self.contact];
    self.callButton.enabled=NO; 
    
}


@end
