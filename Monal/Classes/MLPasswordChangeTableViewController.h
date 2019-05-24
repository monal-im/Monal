//
//  MLPasswordChangeTableViewController.h
//  Monal
//
//  Created by Anurodh Pokharel on 5/22/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "MLConstants.h"
#import "xmpp.h"
#import "MLButtonCell.h"
#import "MLTextInputCell.h"

NS_ASSUME_NONNULL_BEGIN

@interface MLPasswordChangeTableViewController : UITableViewController <UITextFieldDelegate>

@property (nonatomic, strong) xmpp *xmppAccount;
-(IBAction) changePress:(id)sender;

@end


NS_ASSUME_NONNULL_END
