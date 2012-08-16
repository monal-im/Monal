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
#import "MGSplitViewController/MGSplitViewController.h"


@interface callScreen : UIViewController
{

	UILabel* messageLabel;
    UILabel* nameLabel;
    UIButton* endButton; 

    xmpp* jabber;
    
}

-(void) show:(xmpp*) conn:(NSString*) name;
-(void) endPress;


@property (nonatomic) UINavigationController* navigationController;
@property (nonatomic) MGSplitViewController* splitViewController;


@end
