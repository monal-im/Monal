//
//  MLLogInViewController.h
//  Monal
//
//  Created by Anurodh Pokharel on 11/9/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "MLConstants.h"

NS_ASSUME_NONNULL_BEGIN

@interface MLRegisterViewController : UIViewController <UITextFieldDelegate>

@property (nonatomic, weak) IBOutlet UITextField* jid;
@property (nonatomic, weak) IBOutlet UITextField* password;
@property (nonatomic, weak) IBOutlet UITextField* captcha;
@property (nonatomic, weak) IBOutlet UIButton* registerButton;
@property (nonatomic, weak) IBOutlet UIScrollView* scrollView;
@property (nonatomic, weak) IBOutlet UIView* contentView;
@property (nonatomic, weak) IBOutlet UIImageView* captchaImage;

@property (nonatomic, strong) NSString* registerServer;
@property (nonatomic, strong) NSString* registerUsername;
@property (nonatomic, strong) NSString* registerToken;
@property (nonatomic, strong) monal_void_block_t completionHandler; 

-(IBAction) registerAccount:(id)sender;
-(IBAction) useWithoutAccount:(id)sender;
-(IBAction) tapAction:(id)sender;
-(IBAction) openTos:(id)sender;

@end

NS_ASSUME_NONNULL_END
