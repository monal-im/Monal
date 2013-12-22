//
//  ContactsViewController.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/14/13.
//
//

#import <UIKit/UIKit.h>
#import "MLConstants.h"
#import "MLImageManager.h"


//contact cells
#define kusernameKey @"username"
#define kfullNameKey @"fullName"
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
    NSDictionary* _lastSelectedUser;
    UIPopoverController* _popOverController;
}

/**
 This may not be the tab bar (ipad) that this VC is in. But alerts should be shown from it.
 */
@property (nonatomic, strong) UITabBarController* presentationTabBarController;

@property (nonatomic, strong) UITableView* contactsTable;
/**
 Nav controller to push using. Ipad will push on another one. 
 */
@property (nonatomic, strong) UINavigationController* currentNavController;

/**
 Adds an info cell
 */
-(void) showConnecting:(NSDictionary*) info;
/**
 updates the text of an info cell 
 */
-(void) updateConnecting:(NSDictionary*) info;
/**
 removes an info cell 
 */
-(void) hideConnecting:(NSDictionary*) info;

//manage user display
/**
 add or update an online user
 */
-(void) addOnlineUser:(NSDictionary*) user;

/**
 mark user as offline
 */
-(void) removeOnlineUser:(NSDictionary*) user;

/**
 if an account disconnects then clear out those contacts in the list
 */
-(void) clearContactsForAccount: (NSString*) accountNo;

/**
 Receives the new message notice and will update if it is this user.
 */
-(void) handleNewMessage:(NSNotification *)notification;

/**
 Presents a dialog to send a message to an xmppp user to add them as a contact. 
 */
-(void)addContact;


@end 
