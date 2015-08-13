//
//  MLContactDetails.m
//  Monal
//
//  Created by Anurodh Pokharel on 8/13/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import "MLContactDetails.h"

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
//    _buddyName.text =[_contact objectForKey:@"buddy_name"];
//    
//    _buddyMessage.text=[_contact objectForKey:@"status"];
//    if([ _buddyMessage.text isEqualToString:@"(null)"])  _buddyMessage.text=@"";
//    
//    _buddyStatus.text=[_contact objectForKey:@"state"];
//    if([ _buddyStatus.text isEqualToString:@"(null)"])  _buddyStatus.text=@"";
//    
//    _fullName.text=[_contact objectForKey:@"full_name"];
//    if([ _fullName.text isEqualToString:@"(null)"])  _fullName.text=@"";
//    
//    NSArray* parts= [_buddyName.text componentsSeparatedByString:@"@"];
//    if([parts count]>1)
//    {
//        NSString* domain= [parts objectAtIndex:1];
//        if([domain isEqualToString:@"gmail.com"])
//        {
//            //gtalk
//            _protocolImage.image=[UIImage imageNamed:@"GTalk"];
//        }
//        else
//            
//            //xmpp
//            _protocolImage.image=[UIImage imageNamed:@"XMPP"];
//        
//    }
//    NSString* accountNo=[NSString stringWithFormat:@"%@", [_contact objectForKey:@"account_id"]];
//    UIImage* contactImage=[[MLImageManager sharedInstance] getIconForContact:[_contact objectForKey:@"buddy_name"] andAccount:accountNo];
//    _buddyIconView.image=contactImage;
//    
//    NSArray* resources= [[DataLayer sharedInstance] resourcesForContact:[_contact objectForKey:@"buddy_name"]];
//    self.resourcesTextView.text=@"";
//    for(NSDictionary* row in resources)
//    {
//        self.resourcesTextView.text=[NSString stringWithFormat:@"%@\n%@\n",self.resourcesTextView.text, [row objectForKey:@"resource"]];
//        
//    }

}

@end
