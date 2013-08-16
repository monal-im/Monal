//
//  GroupChatViewController.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/14/13.
//
//

#import <UIKit/UIKit.h>

@interface GroupChatViewController : UIViewController

@property (nonatomic, weak) IBOutlet UITextField* roomName; 
@property (nonatomic, weak) IBOutlet UITextField* serverName;
@property (nonatomic, weak) IBOutlet UITextField* password;
@property (nonatomic, weak) IBOutlet UIButton* joinButton;

@end
