//
//  MLDisplaySettings.h
//  Monal
//
//  Created by Anurodh Pokharel on 7/29/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MASPreferencesViewController.h"

@interface MLDisplaySettings : NSViewController <MASPreferencesViewController>

@property (nonatomic, weak) IBOutlet NSButton *chatLogs;
@property (nonatomic, weak) IBOutlet NSButton *playSounds;
@property (nonatomic, weak) IBOutlet NSButton *showMessagePreview;


@property (nonatomic, weak) IBOutlet NSButton *showOffline;
@property (nonatomic, weak) IBOutlet NSButton *sortByStatus;

@end
