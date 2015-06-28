//
//  MLMainWindow.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/28/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import "MLMainWindow.h"
#import "AppDelegate.h"

@interface MLMainWindow ()

@end

@implementation MLMainWindow

- (void)windowDidLoad {
    [super windowDidLoad];
    AppDelegate *appDelegate = [NSApplication sharedApplication].delegate;
    appDelegate.mainWindowController= self; 

}

@end
