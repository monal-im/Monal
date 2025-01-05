//
//  MLAccountPickerViewController.h
//  Monal
//
//  Created by Anurodh Pokharel on 2/10/20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <monalxmpp/MLConstants.h>

NS_ASSUME_NONNULL_BEGIN

@interface MLAccountPickerViewController : UITableViewController

@property (nonatomic, strong) accountCompletion completion;

@end

NS_ASSUME_NONNULL_END
