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

#define kaccountNameKey @"accountName"
#define kinfoTypeKey @"type"
#define kinfoStatusKey @"status"

@interface ContactsViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
{
    NSMutableArray* _infoCells;
    NSMutableArray* _contacts;
    NSMutableArray* _offlineContacts;
}

@property (nonatomic, strong) UITableView* contactsTable;

//manage info display
-(void) showConnecting:(NSDictionary*) info;
-(void) hideConnecting:(NSDictionary*) info;

//manage user display
-(void) addUser:(NSDictionary*) user;
-(void) removeUser:(NSDictionary*) user;
-(void) updateUser:(NSDictionary*) user;


@end 
