//
//  callScreen.h
//  Monal
//
//  Created by Anurodh Pokharel on 8/27/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//


#import <UIKit/UIKit.h>
#import "tools.h"
#import "xmpp.h"



@interface callScreen : UIViewController
{

	UILabel* messageLabel;
    UILabel* nameLabel;
    UIButton* endButton; 

    xmpp* jabber;

    UINavigationController* modalNav;
}

-(void) show:(xmpp*) conn:(NSString*) name;
-(void) endPress;


@property (nonatomic) UINavigationController* navigationController;
@property (nonatomic) UISplitViewController* splitViewController;


@end
