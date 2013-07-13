//
//  ContactsViewController.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/14/13.
//
//

#import <UIKit/UIKit.h>
#define kusernameKey @"username"
#define kaccountNoKey @"accountNo"

@interface ContactsViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
{
    NSMutableArray* _contacts;
}

@property (nonatomic, strong) UITableView* contactsTable;


//manage user display
-(void) addUser:(NSDictionary*) user;
-(void) removeUser:(NSDictionary*) user;
-(void) updateUser:(NSDictionary*) user;

@end 
