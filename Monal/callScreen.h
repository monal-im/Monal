//
//  callScreen.h
//  Monal
//
//  Created by Anurodh Pokharel on 8/27/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//


#import <UIKit/UIKit.h>
#import "tools.h"


@interface callScreen : UIViewController
{
   
	
	UINavigationController* navigationController;
 
	IBOutlet UILabel* buddyName; 

    IBOutlet UIButton* endButton; 
    IBOutlet UIView* topPanel; 
    IBOutlet UIView* bottomPanel; 
    
}

-(void) init:(UINavigationController*) nav;
-(void) show; 


-(IBAction) endPress;


@end
