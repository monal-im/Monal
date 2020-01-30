//
//  MLGroupChatTableViewController.h
//  Monal
//
//  Created by Anurodh Pokharel on 3/25/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "MLConstants.h"
#import <DZNEmptyDataSet/UIScrollView+EmptyDataSet.h>

@interface MLGroupChatTableViewController : UITableViewController <DZNEmptyDataSetSource, DZNEmptyDataSetDelegate>

@property (nonatomic, strong) contactCompletion selectGroup;

@end
