//
//  AccountsViewController.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/14/13.
//
//

#import <UIKit/UIKit.h>
#import <Monal-Swift.h>

@interface AccountsViewController : UITableViewController<MLLQRCodeScannerAccountLoginDeleagte>

@property (nonatomic, strong) UITableView* accountsTable;

-(IBAction)connect:(id)sender;

@end
