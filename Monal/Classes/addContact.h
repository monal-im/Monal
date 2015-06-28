//
//  chat.h
//  SworIM
//
//  Created by Anurodh Pokharel on 1/25/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface addContact : UITableViewController<UIPickerViewDataSource, UIPickerViewDelegate, UITextFieldDelegate>
{

    UITextField* _currentTextField;
    UIPickerView* _accountPicker;
    UIView* _accountPickerView; 
    NSInteger _selectedRow;
    UIBarButtonItem* _closeButton;

}

@property (nonatomic, weak)  UITextField* contactName;
@property (nonatomic, weak)  UITextField* accountName;
@property (nonatomic, weak) IBOutlet UIToolbar* keyboardToolbar;

-(IBAction) addPress;
-(void) closeView;


- (IBAction)toolbarDone:(id)sender;
- (IBAction)toolbarPrevious:(id)sender;
- (IBAction)toolbarNext:(id)sender;

@end
