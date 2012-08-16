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
   
	
	UINavigationController* navigationController;
 
	 UILabel* buddyName; 

     UIButton* endButton; 

    xmpp* jabber;
    
}

-(void) init:(UINavigationController*) nav;
-(void) show:(xmpp*) conn:(NSString*) name;


-(void) endPress;


@end
