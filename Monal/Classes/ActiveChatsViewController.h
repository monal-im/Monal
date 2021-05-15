//
//  ActiveChatsViewController.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/14/13.
//
//

#import <UIKit/UIKit.h>
#import "MLContact.h"
#import <DZNEmptyDataSet/UIScrollView+EmptyDataSet.h>

@interface ActiveChatsViewController : UITableViewController  <DZNEmptyDataSetSource, DZNEmptyDataSetDelegate>

@property (nonatomic, strong) UITableView* chatListTable;
@property (nonatomic, weak) IBOutlet UIBarButtonItem *settingsButton;
@property (nonatomic, weak) IBOutlet UIBarButtonItem *addButton;
@property (nonatomic, weak) IBOutlet UIBarButtonItem *composeButton;

-(void) presentChatWithRow:(MLContact *)row;
-(void) refreshDisplay;

-(void) showContacts;
-(void) deleteConversation;
-(void) showSettings;
-(void) showDetails;

-(IBAction) unwindToActiveChatsViewController:(UIStoryboardSegue*) segue;

@end
