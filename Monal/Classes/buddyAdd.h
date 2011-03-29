//
//  chat.h
//  SworIM
//
//  Created by Anurodh Pokharel on 1/25/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "xmpp.h"



@interface buddyAdd : UIViewController<UITextFieldDelegate>{

	protocol* jabber;
	
	UINavigationController* navigationController;
    UITabBarController* tabbarcontroller;
	
	IBOutlet UITextField* buddyName; 
//	IBOutlet UIButton* cancelButton;
IBOutlet UIScrollView* scroll; 

    UIBarButtonItem *bbiOpenPopOver;
    UIPopoverController *popOverController;
}




-(void) init:(UINavigationController*) nav:(UITabBarController*) tab;
-(void) show:(protocol*)account; 
-(void) show:(protocol*)account:(NSString*) name; 

-(void) showiPad:(protocol*)account; 

-(IBAction) addPress;
//-(IBAction) cancelPress;

-(IBAction)togglePopOverController;

@property (nonatomic, retain) UIPopoverController *popOverController;
@property (nonatomic, retain) UIBarButtonItem *bbiOpenPopOver;

@end
