//
//  MLWelcomeViewController.h
//  Monal
//
//  Created by Anurodh Pokharel on 11/23/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "MLConstants.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^welcomeCompletion)(void);

@interface MLWelcomeViewController : UIViewController

@property (nonatomic, strong) welcomeCompletion completion; 

@end

NS_ASSUME_NONNULL_END
