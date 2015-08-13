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
#import "MLImageManager.h"
#import "MLXMPPManager.h"
#import "MLContactDetails.h"


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
    [NSUserNotificationCenter defaultUserNotificationCenter].delegate= self;
    
}

-(void) updateCurrentContact:(NSDictionary *) contact;
{
    self.contactInfo= contact;
    self.contactNameField.stringValue= [self.contactInfo objectForKey:kFullName];
}

#pragma mark -- segue
- (void)prepareForSegue:(NSStoryboardSegue *)segue sender:(id)sender
{
    if([segue.identifier isEqualToString:@"ContactDetails"]) {
        MLContactDetails *details = (MLContactDetails *)[segue destinationController];
        details.contact=self.contactInfo;
    }
}

- (BOOL)shouldPerformSegueWithIdentifier:(NSString *)identifier sender:(id)sender NS_AVAILABLE_MAC(10_10);
{
    if(!self.contactInfo)
    {
        return  NO;
    }
    else {
        return YES; 
    }
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
        if([[[NSUserDefaults standardUserDefaults] objectForKey:@"MessagePreview"] boolValue]) {
            alert.informativeText=[notification.userInfo objectForKey:@"messageText"];
        } else  {
             alert.informativeText=@"Open app to see message"; 
        }
        
        if([[[NSUserDefaults standardUserDefaults] objectForKey:@"Sound"] boolValue])
        {
            alert.soundName= NSUserNotificationDefaultSoundName;
        }
        
        NSImage *alertImage=  [[MLImageManager sharedInstance] getIconForContact:[notification.userInfo objectForKey:@"from"] andAccount:[notification.userInfo objectForKey:@"accountNo"]];
        alert.contentImage= alertImage;
        alert.hasReplyButton=YES;
        alert.userInfo= notification.userInfo;
        [[NSUserNotificationCenter defaultUserNotificationCenter] scheduleNotification:alert];
    }
    

    [[DataLayer sharedInstance] countUnreadMessagesWithCompletion:^(NSNumber * result) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if([result integerValue]>0) {
                [[[NSApplication sharedApplication] dockTile] setBadgeLabel:[NSString stringWithFormat:@"%@", result]];
                [[NSApplication sharedApplication] requestUserAttention:NSInformationalRequest];
            }
        });
        
    }];


}

#pragma mark - notificaiton delegate

- (void)userNotificationCenter:(NSUserNotificationCenter * )center didActivateNotification:(NSUserNotification *  )notification
{
    [self showWindow:self];
    
    NSDictionary *userInfo= notification.userInfo;
    [[MLXMPPManager sharedInstance].contactVC showConversationForContact:userInfo];
    
    if(notification.activationType==NSUserNotificationActivationTypeReplied)
    {
        [[MLXMPPManager sharedInstance].contactVC.chatViewController sendMessage:notification.response.string andMessageID:nil];
        
    }
}


#pragma mark - Window delegate
- (void)windowDidChangeOcclusionState:(NSNotification *)notification
{
    if ([[notification object] occlusionState]  &  NSWindowOcclusionStateVisible) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kMonalWindowVisible object:nil];
        // visible
    } else {
        // occluded
    }
}

@end
