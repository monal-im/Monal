//
//  ActiveChatsViewController.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/14/13.
//
//

#import <UIKit/UIKit.h>

@interface ActiveChatsViewController : UITableViewController 
{
    NSArray* _contacts;
    NSDictionary* _lastSelectedUser;
}

@property (nonatomic, strong) UITableView* chatListTable;

/**
 Closes all active chats
 */
-(void) closeAll;

@end
