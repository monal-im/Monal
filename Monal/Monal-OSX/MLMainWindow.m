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

@property (nonatomic, strong) NSDictionary *contactInfo;

@end

@implementation MLMainWindow

- (void)windowDidLoad {
    [super windowDidLoad];
    AppDelegate *appDelegate = [NSApplication sharedApplication].delegate;
    appDelegate.mainWindowController= self; 

}

-(void) updateCurrentContact:(NSDictionary *) contact;
{
    self.contactInfo= contact;
    self.contactNameField.stringValue= [self.contactInfo objectForKey:@"full_name"];
}


@end
