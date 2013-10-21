//
//  GroupChatViewController.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/14/13.
//
//

#import <UIKit/UIKit.h>

@interface GroupChatViewController : UIViewController <UIPickerViewDataSource, UIPickerViewDelegate, UITextFieldDelegate>
{
    UIPickerView* _accountPicker;
    UIView* _accountPickerView;
    IBOutlet UIToolbar* _keyboardToolbar;
    UITextField* _currentTextField;
    BOOL _hasRequestedRooms; 
    NSInteger _selectedRow;
}

@property (nonatomic, weak) IBOutlet UITextField* roomName; 
@property (nonatomic, weak) IBOutlet UITextField* accountName;
@property (nonatomic, weak) IBOutlet UITextField* password;
@property (nonatomic, weak) IBOutlet UIButton* joinButton;
@property (nonatomic, weak) IBOutlet UIButton* roomButton;

- (IBAction)toolbarDone:(id)sender;
- (IBAction)toolbarPrevious:(id)sender;
- (IBAction)toolbarNext:(id)sender;

- (IBAction)getRooms:(id)sender;
- (IBAction)joinRoom:(id)sender;

@end
