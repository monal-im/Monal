//
//  ChatLogsViewController.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/14/13.
//
//

#import <UIKit/UIKit.h>

@interface ChatLogsViewController : UITableViewController
{
    NSArray* _tableData;
}

@property (nonatomic, weak) UITableView* chatLogTable;

@end
