//
//  ChatLogAccountDetailViewController.h
//  Monal
//
//  Created by Anurodh Pokharel on 12/12/13.
//
//

#import <UIKit/UIKit.h>
#import "DataLayer.h"
#import "ChatLogContactViewController.h"

@interface ChatLogAccountDetailViewController : UITableViewController

@property (nonatomic, strong) NSString* accountId;
@property (nonatomic, strong) NSString* accountName;
@property (nonatomic, strong) NSMutableArray* tableData;



@end
