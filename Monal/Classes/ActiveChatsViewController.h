//
//  ActiveChatsViewController.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/14/13.
//
//

#import <UIKit/UIKit.h>

@interface ActiveChatsViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
{
    NSArray* _contacts;
    NSDictionary* _lastSelectedUser;
}


@property (nonatomic, strong) UITableView* chatListTable;
@end