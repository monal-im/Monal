//
//  ChatLogAccountDetailViewController.h
//  Monal
//
//  Created by Anurodh Pokharel on 12/12/13.
//
//

#import "ChatLogsViewController.h"
#import "DataLayer.h"

@interface ChatLogAccountDetailViewController : UITableViewController
{
    NSString* _accountId;
    NSString* _accountName;
    NSArray* _tableData;
}

/**
 Initilizes with Account name and id
 */
-(id) initWithAccountId:(NSString*) accountId andName:(NSString*) accountName;

@end
