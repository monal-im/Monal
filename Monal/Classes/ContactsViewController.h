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
#import "MLContact.h"
#import <UIScrollView+EmptyDataSet.h>

@interface ContactsViewController : UITableViewController  <UISearchResultsUpdating, UISearchControllerDelegate
,DZNEmptyDataSetSource, DZNEmptyDataSetDelegate>

@property (nonatomic, weak) UITableView* contactsTable;
@property (nonatomic, strong) contactCompletion selectContact; 

-(IBAction) close:(id) sender;

@end 
