//
//  chat.h
//  SworIM
//
//  Created by Anurodh Pokharel on 1/25/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface addContact : UIViewController<UIPickerViewDataSource, UIPickerViewDelegate, UITextFieldDelegate>
{
		
	IBOutlet UITextField* _buddyName;
    IBOutlet UITextField* _accountName;
    UITextField* _currentTextField;
    UIPickerView* _accountPicker;
    UIView* _accountPickerView; 
    NSInteger _selectedRow;
    
    IBOutlet UILabel* _caption;
     UIBarButtonItem* _closeButton;
    IBOutlet UIButton* _addButton;
    IBOutlet UIToolbar* _keyboardToolbar;
}


-(IBAction) addPress;
-(void) closeView;


- (IBAction)toolbarDone:(id)sender;
- (IBAction)toolbarPrevious:(id)sender;
- (IBAction)toolbarNext:(id)sender;

@end
