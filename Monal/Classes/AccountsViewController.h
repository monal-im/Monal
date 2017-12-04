//
//  AccountsViewController.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/14/13.
//
//

#import <UIKit/UIKit.h>


@interface AccountsViewController : UITableViewController
{
    NSArray* _accountList;
    NSArray* _protocolList; 
}


@property (nonatomic, strong) UITableView* accountsTable;

@end
