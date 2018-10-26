//
//  MLSelectionController.h
//  Monal
//
//  Created by Anurodh Pokharel on 10/26/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
typedef void(^selectionResult)(NSString *);

@interface MLSelectionController : UITableViewController

@property (nonatomic, assign) selectionResult completion;
@property (nonatomic, strong) NSArray *options; // an Array of stirngs
@property (nonatomic, strong) NSString *selection;
@end

NS_ASSUME_NONNULL_END
