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
#import <DZNEmptyDataSet/UIScrollView+EmptyDataSet.h>

@interface ContactsViewController : UITableViewController  <UISearchResultsUpdating, UISearchControllerDelegate, UIViewControllerPreviewingDelegate,DZNEmptyDataSetSource, DZNEmptyDataSetDelegate>
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
 if an account disconnects then clear out those contacts in the list
 */
-(void) clearContactsForAccount: (NSString*) accountNo;

/**
 Receives the new message notice and will update if it is this user.
 */
-(void) handleNewMessage:(NSNotification *)notification;



@end 
