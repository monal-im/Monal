//
//  chat.h
//  SworIM
//
//  Created by Anurodh Pokharel on 1/25/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "tools.h"
#import "SworIMAppDelegate.h"


@interface askTempPass : UIViewController<UITextFieldDelegate>{

	
	
	//UINavigationController* navigationController;
    UITabBarController* tabbarcontroller;
	
	IBOutlet UITextField* passwordField; 
    //	IBOutlet UIButton* cancelButton;
    IBOutlet UIScrollView* scroll; 
    UIViewController* theApp; 

  
}




-(void) init:(UITabBarController*) tab;
-(void) show; 



-(IBAction) addPress;
-(IBAction) closePress;



@end
