//
//  ChatLogsViewController.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/14/13.
//
//

#import <UIKit/UIKit.h>

@interface ChatLogsViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>


@property (nonatomic, strong) UITableView* chatLogTable;

@end
