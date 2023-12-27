//
//  ShareViewController.m
//  shareSheet
//
//  Created by Anurodh Pokharel on 9/10/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import "ShareViewController.h"
#import "MLSelectionController.h"

#import "UIColor+Theme.h"
#import "MLContact.h"
#import "MLConstants.h"
#import "HelperTools.h"
#import "DataLayer.h"
#import "MLFiletransfer.h"
#import "IPC.h"

#import <MapKit/MapKit.h>
#import <MobileCoreServices/MobileCoreServices.h>

@import Intents;
@import UniformTypeIdentifiers;

@interface ShareViewController ()

@property (nonatomic, strong) NSArray<NSDictionary*>* accounts;
@property (nonatomic, strong) NSArray<MLContact*>* recipients;
@property (nonatomic, strong) MLContact* recipient;
@property (nonatomic, strong) NSDictionary* account;
@property (nonatomic, strong) MLContact* intentContact;

@end

//TODO: use this approach, but with swiftui: https://diamantidis.github.io/2020/01/11/share-extension-custom-ui
@implementation ShareViewController

+(void) initialize
{
    [HelperTools initSystem];
    
    //init IPC
    [IPC initializeForProcess:@"ShareSheetExtension"];
    
    //log startup
    DDLogInfo(@"Share Sheet Extension started: %@", [HelperTools appBuildVersionInfoFor:MLVersionTypeLog]);
    [DDLog flushLog];
}

-(void) viewDidLoad
{
    [super viewDidLoad];
    [self.navigationController.navigationBar setTintColor:[UIColor whiteColor]];
    [self.navigationController.navigationBar setBackgroundColor:[UIColor monaldarkGreen]];
    self.navigationController.navigationItem.title = NSLocalizedString(@"Monal", @"");
    
    if(self.extensionContext.intent != nil && [self.extensionContext.intent isKindOfClass:[INSendMessageIntent class]])
    {
        INSendMessageIntent* intent = (INSendMessageIntent*)self.extensionContext.intent;
        self.intentContact = [HelperTools unserializeData:[intent.conversationIdentifier dataUsingEncoding:NSISOLatin1StringEncoding]];
        [self.intentContact refresh];       //make sure we are up to date
    }
}

- (void) presentationAnimationDidFinish
{
    // list all contacts, not only active chats
    // that will clutter the list of selectable contacts, but you can always use sirikit interactions
    // to get the recently used contacts listed
    NSMutableArray<MLContact*>* recipients = [[DataLayer sharedInstance] contactList];
    
    self.recipients = recipients;
    self.accounts = [[DataLayer sharedInstance] enabledAccountList];

    if(self.intentContact != nil)
    {
        //check if intentContact is in enabled account list
        for(NSDictionary* accountToCheck in self.accounts)
        {
            NSNumber* accountNo = [accountToCheck objectForKey:@"account_id"];
            if(accountNo.intValue == self.intentContact.accountId.intValue)
            {
                self.recipient = self.intentContact;
                self.account = accountToCheck;
                break;
            }
        }
    }
    
    //no intent given or intent contact not found --> select initial recipient (contact with most recent interaction)
    if(!self.account || !self.recipient)
    {
        BOOL recipientFound = NO;
        for(MLContact* recipient in self.recipients)
        {
            for(NSDictionary* accountToCheck in self.accounts)
            {
                NSNumber* accountNo = [accountToCheck objectForKey:@"account_id"];
                if(accountNo.intValue == recipient.accountId.intValue)
                {
                    self.recipient = recipient;
                    self.account = accountToCheck;
                    recipientFound = YES;
                    break;
                }
                if(recipientFound == YES)
                    break;
            }
        }
    }
    
    [self reloadConfigurationItems];
}

-(MLContact* _Nullable) getLastContactForAccount:(NSNumber*) accountNo
{
    for(MLContact* recipient in self.recipients) {
        if(recipient.accountId.intValue == accountNo.intValue) {
            return recipient;
        }
    }
    return nil;
}

-(BOOL) isContentValid
{
    if(self.recipient != nil && self.account != nil)
        return YES;
    return NO;
}

-(void) didSelectPost
{
    DDLogVerbose(@"input items: %@", self.extensionContext.inputItems);
    NSExtensionItem* item = self.extensionContext.inputItems.firstObject;
    DDLogVerbose(@"Attachments = %@", item.attachments);

    __block uint32_t loading = 0;       //no need for @synchronized etc., because we access this var exclusively from the main thread
    __block uint32_t saved = 0;         //no need for @synchronized etc., because we access this var exclusively from the main thread
    monal_void_block_t checkIfDone = ^{
        if(loading == 0)
        {
            if(self.contentText && [self.contentText length] > 0)
            {
                NSMutableDictionary* payload = [NSMutableDictionary new];
                payload[@"account_id"] = self.recipient.accountId;
                payload[@"recipient"] = self.recipient.contactJid;
                payload[@"type"] = @"text";
                payload[@"data"] = self.contentText;
                DDLogDebug(@"Adding shareSheet comment payload: %@", payload);
                [[DataLayer sharedInstance] addShareSheetPayload:payload];
                saved++;
            }
            [self.extensionContext completeRequestReturningItems:@[] completionHandler:^(BOOL expired __unused) {
                if(saved > 0)
                    [self openMainApp];
            }];
        }
    };
    for(NSItemProvider* provider in item.attachments)
    {
//         //text shares are also shared via comment field, so ignore them
//         if([provider hasItemConformingToTypeIdentifier:UTTypePlainText.identifier])
//             continue;
        DDLogVerbose(@"handling(%u) %@", loading, provider);
        loading++;
        [HelperTools handleUploadItemProvider:provider withCompletionHandler:^(NSMutableDictionary* payload) {
            DDLogVerbose(@"Got handleUploadItemProvider callback with payload: %@", payload);
            dispatch_async(dispatch_get_main_queue(), ^{
                if(payload == nil || payload[@"error"] != nil)
                {
                    DDLogError(@"Could not save payload for sending: %@", payload[@"error"]);
                    NSString* message = NSLocalizedString(@"Monal was not able to send your attachment!", @"");
                    if(payload[@"error"] != nil)
                        message = [NSString stringWithFormat:NSLocalizedString(@"Monal was not able to send your attachment: %@", @""), [payload[@"error"] localizedDescription]];
                    UIAlertController* unknownItemWarning = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Could not send", @"")
                                                                                message:message preferredStyle:UIAlertControllerStyleAlert];
                    [unknownItemWarning addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Abort", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
                        [unknownItemWarning dismissViewControllerAnimated:YES completion:nil];
                        [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
                        loading--;
                        checkIfDone();
                    }]];
                    [self presentViewController:unknownItemWarning animated:YES completion:nil];
                    return;
                }
                
                //text shares are also shared via comment field, so ignore them, if they contain the same contents
                if([provider hasItemConformingToTypeIdentifier:UTTypePlainText.identifier] && self.contentText && [self.contentText length] > 0 && [payload[@"data"] isKindOfClass:[NSString class]] && [self.contentText isEqualToString:payload[@"data"]])
                {
                    DDLogWarn(@"Ignoring text payload because already sent via comment field");
                    loading--;
                    checkIfDone();
                    return;
                }
                
                payload[@"account_id"] = self.recipient.accountId;
                payload[@"recipient"] = self.recipient.contactJid;
                DDLogDebug(@"Adding shareSheet payload(%u): %@", loading, payload);
                [[DataLayer sharedInstance] addShareSheetPayload:payload];
                saved++;
                loading--;
                checkIfDone();
            });
        }];
    }
    checkIfDone();
}

-(NSArray*) configurationItems
{
    NSMutableArray* toreturn = [NSMutableArray new];
    if(self.accounts.count > 1)
    {
        SLComposeSheetConfigurationItem* accountSelector = [SLComposeSheetConfigurationItem new];
        accountSelector.title = NSLocalizedString(@"Account", @"ShareViewController: Account");

        accountSelector.value = [NSString stringWithFormat:@"%@@%@", [self.account objectForKey:@"username"], [self.account objectForKey:@"domain"]];
        accountSelector.tapHandler = ^{
            UIStoryboard* iosShareStoryboard = [UIStoryboard storyboardWithName:@"iosShare" bundle:nil];
            MLSelectionController* controller = (MLSelectionController*)[iosShareStoryboard instantiateViewControllerWithIdentifier:@"accounts"];
            controller.options = self.accounts;
            controller.completion = ^(NSDictionary* selectedAccount)
            {
                if(selectedAccount != nil) {
                    self.account = selectedAccount;
                }
                else {
                    self.account = self.accounts[0]; // at least one account is present (count > 0)
                }
                self.recipient = [self getLastContactForAccount:[self.account objectForKey:@"account_id"]];
                [self reloadConfigurationItems];
            };
            
            [self pushConfigurationViewController:controller];
        };
        [toreturn addObject:accountSelector];
    }
    
    if(!self.account && self.accounts.count > 0)
        self.account = [self.accounts objectAtIndex:0];

    SLComposeSheetConfigurationItem* recipient = [SLComposeSheetConfigurationItem new];
    recipient.title = NSLocalizedString(@"Recipient", @"shareViewController: recipient");
    recipient.value = [NSString stringWithFormat:@"%@ (%@)", self.recipient.contactDisplayName, self.recipient.contactJid];
    recipient.tapHandler = ^{
        UIStoryboard* iosShareStoryboard = [UIStoryboard storyboardWithName:@"iosShare" bundle:nil];
        MLSelectionController* controller = (MLSelectionController *)[iosShareStoryboard instantiateViewControllerWithIdentifier:@"contacts"];

        // Create list of recipients for the selected account
        NSMutableArray<NSDictionary*>* recipientsToShow = [NSMutableArray new];
        for (MLContact* contact in self.recipients)
        {
            // only show contacts from the selected account
            NSNumber* accountNo = [self.account objectForKey:@"account_id"];
            if(contact.accountId.intValue == accountNo.intValue)
                [recipientsToShow addObject:@{@"contact": contact}];
        }

        controller.options = recipientsToShow;
        controller.completion = ^(NSDictionary* selectedRecipient) {
            MLContact* contact = [selectedRecipient objectForKey:@"contact"];
            if(contact)
                self.recipient = contact;
            else
                self.recipient = nil;
            [self reloadConfigurationItems];
        };
        
        [self pushConfigurationViewController:controller];
    };
    [toreturn addObject:recipient];
    [self validateContent];
    return toreturn;
}

-(void) openURL:(NSURL*) url
{
    UInt16 iterations = 0;
    SEL openURLSelector = NSSelectorFromString(@"openURL:");
    UIResponder* responder = self;
    while((responder = [responder nextResponder]) != nil && iterations++ < 16)
        if([responder respondsToSelector:openURLSelector] == YES)
        {
            UIApplication* app = (UIApplication*)responder;
            if(app != nil)
            {
                [app performSelector:@selector(openURL:) withObject:url];
                break;
            }
        }
}

-(void) openMainApp
{
    DDLogInfo(@"Now opening mainapp via %@...", kMonalOpenURL);
    NSURL* mainAppUrl = kMonalOpenURL;
    [self openURL:mainAppUrl];
}

@end
