//
//  MLRegSuccessViewController.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/3/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "MLConstants.h"

NS_ASSUME_NONNULL_BEGIN

@interface MLRegSuccessViewController : UIViewController

@property (nonatomic, strong) NSString* registeredAccount;
@property (nonatomic, weak) IBOutlet UILabel* jid;
@property (nonatomic, weak) IBOutlet UIImageView* QRCode;
@property (nonatomic) monal_void_block_t completionHandler; 

-(IBAction) close:(id) sender;

@end

NS_ASSUME_NONNULL_END
