//
//  ContactsViewController.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/14/13.
//
//

#import <UIKit/UIKit.h>
#import "MLConstants.h"

//contact cells
#define kusernameKey @"username"
#define kaccountNoKey @"accountNo"
#define kstateKey @"state"
#define kstatusKey @"status"

//info cells
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
/**
 add or update an online user
 */
-(void) addUser:(NSDictionary*) user;

/**
 mark user as offline
 */
-(void) removeUser:(NSDictionary*) user;

/**
 Receives the new message notice and will update if it is this user.
 */
-(void) handleNewMessage:(NSNotification *)notification;


@end 
