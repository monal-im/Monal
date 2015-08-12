//
//  MLMainWindow.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/28/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import "MLMainWindow.h"
#import "AppDelegate.h"
#import "DataLayer.h"
#import "MLConstants.h"


@interface MLMainWindow ()

@property (nonatomic, strong) NSDictionary *contactInfo;

@end

@implementation MLMainWindow

- (void)windowDidLoad {
    [super windowDidLoad];
    AppDelegate *appDelegate = [NSApplication sharedApplication].delegate;
    appDelegate.mainWindowController= self;
    
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(handleNewMessage:) name:kMonalNewMessageNotice object:nil];
    
}

-(void) updateCurrentContact:(NSDictionary *) contact;
{
    self.contactInfo= contact;
    self.contactNameField.stringValue= [self.contactInfo objectForKey:@"full_name"];
}


#pragma mark -- notifications
-(void) handleNewMessage:(NSNotification *)notification;
{
    if(self.window.occlusionState & NSWindowOcclusionStateVisible) {
        
    }
    else {
        NSUserNotification *alert =[[NSUserNotification alloc] init];
        NSString* acctString =[NSString stringWithFormat:@"%ld", (long)[[notification.userInfo objectForKey:@"accountNo"] integerValue]];
        NSString* fullName =[[DataLayer sharedInstance] fullName:[notification.userInfo objectForKey:@"from"] forAccount:acctString];
        
        NSString* nameToShow=[notification.userInfo objectForKey:@"from"];
        if([fullName length]>0) nameToShow=fullName;
        
        alert.title= nameToShow;
        alert.informativeText=[notification.userInfo objectForKey:@"messageText"];
        
        //alert.contentImage;
        
        [[NSUserNotificationCenter defaultUserNotificationCenter] scheduleNotification:alert];
    }
}

@end
