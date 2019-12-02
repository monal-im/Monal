//
//  MLResourcesTableViewController.h
//  Monal
//
//  Created by Anurodh Pokharel on 12/30/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "MLContact.h"

NS_ASSUME_NONNULL_BEGIN

@interface MLResourcesTableViewController : UITableViewController
@property (nonatomic, strong) MLContact *contact;
@end

NS_ASSUME_NONNULL_END
