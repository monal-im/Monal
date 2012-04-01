//
//  chat.h
//  SworIM
//
//  Created by Anurodh Pokharel on 1/25/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "xmpp.h"



@interface GroupChat : UIViewController<UITextFieldDelegate>{

	xmpp* jabber;
	UINavigationController* nav; 
IBOutlet UIScrollView* scroll; 
	
	IBOutlet UITextField* room; 
    IBOutlet UITextField* server; 
    IBOutlet UITextField* password; 

}
 
-(void) hideKeyboard;

-(IBAction) join;

@property (nonatomic) protocol* jabber; 
@property (nonatomic) UINavigationController* nav; 

@end
