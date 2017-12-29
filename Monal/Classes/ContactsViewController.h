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


@interface ContactsViewController : UITableViewController

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
 Presents a specific chat
 */
-(void) presentChatWithName:(NSString *)buddyname account:(NSNumber *) account ;


@end 
