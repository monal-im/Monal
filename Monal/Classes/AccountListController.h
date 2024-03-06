//
//  AccountListController.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/14/13.
//
//

#import <UIKit/UIKit.h>
#import <Monal-Swift.h>
#import "MLSwitchCell.h"

@interface AccountListController : UITableViewController

-(NSUInteger) getAccountNum;
-(NSNumber*) getAccountNoByIndex:(NSUInteger) index;
-(NSString *) getAccountNameByIndex:(NSUInteger) index;
-(void) setupAccountsView;
-(void) refreshAccountList;
-(void) initContactCell:(MLSwitchCell*) cell forAccNo:(NSUInteger) accNo;
@end
