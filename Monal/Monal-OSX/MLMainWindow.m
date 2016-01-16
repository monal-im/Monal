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
    [nc addObserver:self selector:@selector(handleConnect:) name:kMLHasConnectedNotice object:nil];
    [NSUserNotificationCenter defaultUserNotificationCenter].delegate= self;
    
    
}

-(void) updateCurrentContact:(NSDictionary *) contact;
{
    self.contactInfo= contact;
    self.contactNameField.stringValue= [self.contactInfo objectForKey:kFullName];
}

#pragma mark - segue
- (void)prepareForSegue:(NSStoryboardSegue *)segue sender:(id)sender
{
    if([segue.identifier isEqualToString:@"ContactDetails"]) {
        MLContactDetails *details = (MLContactDetails *)[segue destinationController];
        details.contact=self.contactInfo;
    }
}

- (BOOL)shouldPerformSegueWithIdentifier:(NSString *)identifier sender:(id)sender NS_AVAILABLE_MAC(10_10);
{
    if([identifier isEqualToString:@"ContactDetails"]) {
        if(!self.contactInfo)
        {
            return  NO;
        }
        else {
            return YES;
        }
    } else {
        return YES;
    }
}




#pragma mark - notifications
-(void) handleConnect:(NSNotification *)notification
{
    NSString* nameToShow=[notification.object objectForKey:@"AccountName"];
    NSUserNotification *alert =[[NSUserNotification alloc] init];
    NSString* messageString =[NSString stringWithFormat:@"Account %@ has connected.", nameToShow];
    alert.informativeText =messageString;
    [[NSUserNotificationCenter defaultUserNotificationCenter] scheduleNotification:alert];
    
}

-(void) handleNewMessage:(NSNotification *)notification;
{
    BOOL showNotification =YES;
    NSUserNotification *alert =[[NSUserNotification alloc] init];
    NSString* acctString =[NSString stringWithFormat:@"%ld", (long)[[notification.userInfo objectForKey:@"accountNo"] integerValue]];
    NSString* nameToShow=[notification.userInfo objectForKey:@"from"];

    
    if(self.window.occlusionState & NSWindowOcclusionStateVisible) {
        if(self.window.isKeyWindow) {
            if([nameToShow isEqualToString:[self.contactInfo objectForKey:kContactName]])
            {
                showNotification= NO;
            }
        }
    }
    
    
    if (showNotification) {
   
        NSString* fullName =[[DataLayer sharedInstance] fullName:[notification.userInfo objectForKey:@"from"] forAccount:acctString];
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

#pragma mark - UI Actions
-(IBAction)showContactsTab:(id)sender
{
    [self.contactsViewController toggleContactsTab];
}

-(IBAction)showActiveChatTab:(id)sender;
{
     [self.contactsViewController toggleActiveChatTab];
}

-(IBAction)showContactDetails:(id)sender
{
    [self performSegueWithIdentifier:@"ContactDetails" sender:self];
}

-(IBAction)showAddContactSheet:(id)sender
{
    [self performSegueWithIdentifier:@"AddContact" sender:self];
}


#pragma mark - notificaiton delegate

- (void)userNotificationCenter:(NSUserNotificationCenter * )center didActivateNotification:(NSUserNotification *  )notification
{
    NSDictionary *userInfo= notification.userInfo;
    [[MLXMPPManager sharedInstance].contactVC showConversationForContact:userInfo];
   
    if(notification.activationType==NSUserNotificationActivationTypeReplied)
    {
        if(notification.response.string.length>0) {
            if([[MLXMPPManager sharedInstance].contactVC.chatViewController.contactName isEqualToString:[userInfo objectForKey:@"actuallyfrom"]]) {
                [[MLXMPPManager sharedInstance].contactVC.chatViewController sendMessage:notification.response.string andMessageID:nil];
            }
            else  {
                NSLog(@"error cant send to wrong contact");
            }
        }
        
    }
    else  {
        [[MLXMPPManager sharedInstance].contactVC highlightCellForCurrentContact];
        [self showWindow:self];
    }
}


#pragma mark - Window delegate
- (void)windowDidChangeOcclusionState:(NSNotification *)notification
{
    if ([[notification object] occlusionState]  &  NSWindowOcclusionStateVisible) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kMonalWindowVisible object:nil];
        // visible
        if(self.window.isKeyWindow)
        {
            [[NSUserNotificationCenter defaultUserNotificationCenter] removeAllDeliveredNotifications];
        }
        
    } else {
        // occluded
    }
}


@end
