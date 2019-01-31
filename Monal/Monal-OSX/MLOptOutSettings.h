//
//  MLOptOutSettings.h
//  Monal-OSX
//
//  Created by Anurodh Pokharel on 1/31/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MASPreferencesViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface MLOptOutSettings : NSViewController  <MASPreferencesViewController>
@property (nonatomic, weak) IBOutlet NSButton *crashlytics;
@end

NS_ASSUME_NONNULL_END
