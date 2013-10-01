//
//  chat.h
//  SworIM
//
//  Created by Anurodh Pokharel on 1/25/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface addContact : UIViewController<UITextFieldDelegate>{
		
	IBOutlet UITextField* _buddyName;
    IBOutlet UILabel* _caption;
    IBOutlet UIBarButtonItem* _closeButton;
}


-(IBAction) addPress;
-(void) closeView;

@end
