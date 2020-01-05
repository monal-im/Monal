//
//  MLSelectionController.h
//  Monal
//
//  Created by Anurodh Pokharel on 10/26/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "MLContact.h"

NS_ASSUME_NONNULL_BEGIN
typedef void(^selectionResult)(NSDictionary *);

@interface MLSelectionController : UITableViewController

@property (nonatomic, copy) selectionResult completion;
@property (nonatomic, strong) NSArray *options; // an Array of MlContact
@property (nonatomic, strong) NSDictionary *selection;
@end

NS_ASSUME_NONNULL_END
