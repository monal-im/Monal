//
//  MLJoinGroupViewController.h
//  Monal
//
//  Created by Anurodh Pokharel on 4/1/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "MLConstants.h"

@interface MLJoinGroupViewController : UITableViewController <UITextFieldDelegate>
{
      NSInteger _selectedRow;
}

@property (nonatomic, strong) NSDictionary *groupData;
@property (nonatomic, strong) contactCompletion completion;

@end
