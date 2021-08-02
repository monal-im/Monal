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

#import <MapKit/MapKit.h>

@interface ShareViewController ()

@property (nonatomic, strong) NSArray<NSDictionary*>* accounts;
@property (nonatomic, strong) NSArray<MLContact*>* recipients;
@property (nonatomic, strong) MLContact* recipient;
@property (nonatomic, strong) NSDictionary* account;

@end

// Magic const
const u_int32_t MagicPublicUrl = 1 << 0;
const u_int32_t MagicPlainTxt = 1 << 1;
const u_int32_t MagicMapKitItem = 1 << 2;

@implementation ShareViewController

+(void) initialize
{
    [HelperTools configureLogging];
    
    //log unhandled exceptions
    NSSetUncaughtExceptionHandler(&logException);
}

-(void) viewDidLoad
{
    [super viewDidLoad];
    [self.navigationController.navigationBar setTintColor:[UIColor whiteColor]];
    [self.navigationController.navigationBar setBackgroundColor:[UIColor monaldarkGreen]];
    self.navigationController.navigationItem.title = NSLocalizedString(@"Monal", @"");
}

- (void) presentationAnimationDidFinish
{
    DDLogInfo(@"Monal ShareViewController presentationAnimationDidFinish");
    
    // list pinned chats above normal chats
    NSMutableArray<MLContact*>* recipients = [[DataLayer sharedInstance] activeContactsWithPinned:YES];
    [recipients addObjectsFromArray:[[DataLayer sharedInstance] activeContactsWithPinned:NO]];
    
    self.recipients = recipients;
    self.accounts = [[DataLayer sharedInstance] enabledAccountList];

    BOOL recipientFound = NO;
    for(MLContact* recipient in self.recipients)
    {
        for(NSDictionary* accountToCheck in self.accounts)
            if([[NSString stringWithFormat:@"%@", [accountToCheck objectForKey:@"account_id"]] isEqualToString:recipient.accountId] == YES)
            {
                self.recipient = recipient;
                self.account = accountToCheck;
                recipientFound = YES;
                break;
            }
        if(recipientFound == YES)
            break;
    }
    [self reloadConfigurationItems];
}

-(MLContact* _Nullable) getLastContactForAccount:(NSString*) accountNo
{
    for(MLContact* recipient in self.recipients) {
        if([recipient.accountId isEqualToString:accountNo] == YES) {
            return recipient;
        }
    }
    return nil;
}

-(BOOL) isContentValid
{
    if(self.recipient != nil && self.account != nil)
        return YES;
    else
        return NO;
}

-(void) didSelectPost
{
    NSExtensionItem* item = self.extensionContext.inputItems.firstObject;
    DDLogVerbose(@"Attachments = %@", item.attachments);

    u_int32_t magicIdentifyer = 0;
    NSMutableDictionary<NSNumber*, NSItemProvider*>* magicIdentifyerDic = [[NSMutableDictionary alloc] init];

    for(NSItemProvider* provider in item.attachments)
    {
        DDLogInfo(@"ShareProvider: %@", provider.registeredTypeIdentifiers);
        if([provider hasItemConformingToTypeIdentifier:@"public.url"])
        {
           magicIdentifyer |= MagicPublicUrl;
           [magicIdentifyerDic setObject:provider forKey:[NSNumber numberWithUnsignedInt:MagicPublicUrl]];
        }
        if([provider hasItemConformingToTypeIdentifier:@"public.plain-text"])
        {
           magicIdentifyer |= MagicPlainTxt;
           [magicIdentifyerDic setObject:provider forKey:[NSNumber numberWithUnsignedInt:MagicPlainTxt]];
        }
        if([provider hasItemConformingToTypeIdentifier:@"com.apple.mapkit.map-item"])
        {
           magicIdentifyer |= MagicMapKitItem;
           [magicIdentifyerDic setObject:provider forKey:[NSNumber numberWithUnsignedInt:MagicMapKitItem]];
        }
    }
    NSMutableDictionary* payload = [[NSMutableDictionary alloc] init];
    payload[@"account_id"] = self.recipient.accountId;
    payload[@"recipient"] = self.recipient.contactJid;
    payload[@"comment"] = self.contentText;

    // use best matching providers
    if((magicIdentifyer & MagicMapKitItem) > 0) {
        // convert map item to geo:
        NSItemProvider* provider = [magicIdentifyerDic objectForKey:[NSNumber numberWithUnsignedInt:MagicMapKitItem]];
        [provider loadItemForTypeIdentifier:@"com.apple.mapkit.map-item" options:NULL completionHandler:^(NSData*  _Nullable item, NSError * _Null_unspecified error) {
            NSError* err;
            MKMapItem* mapItem = [NSKeyedUnarchiver unarchivedObjectOfClass:[MKMapItem class] fromData:item error:&err];
            DDLogWarn(@"%@", err);
            payload[@"type"] = @"geo";
            payload[@"data"] = [NSString stringWithFormat:@"geo:%f,%f", mapItem.placemark.coordinate.latitude, mapItem.placemark.coordinate.longitude];
            [self savePayloadMsgAndComplete:payload];
        }];
    }
    else if((magicIdentifyer & MagicPublicUrl) > 0)
    {
        NSItemProvider* provider = [magicIdentifyerDic objectForKey:[NSNumber numberWithUnsignedInt:MagicPublicUrl]];
        [provider loadItemForTypeIdentifier:@"public.url" options:NULL completionHandler:^(NSURL<NSSecureCoding>*  _Nullable item, NSError * _Null_unspecified error) {
            payload[@"type"] = @"url";
            payload[@"data"] = item.absoluteString;
            [self savePayloadMsgAndComplete:payload];
        }];
    }
    else if((magicIdentifyer & MagicPlainTxt) > 0)
    {
        payload[@"type"] = @"text";
        payload[@"data"] = self.contentText;
        payload[@"comment"] = @"";
        [self savePayloadMsgAndComplete:payload];
    }
}

-(void) savePayloadMsgAndComplete:(NSDictionary*) payload
{
    [[DataLayer sharedInstance] addShareSheetPayload:payload];
    [self.extensionContext completeRequestReturningItems:@[] completionHandler:^(BOOL expired) {
        [self openMainApp:payload[@"recipient"]];
    }];
}

-(NSArray*) configurationItems
{
    NSMutableArray* toreturn = [[NSMutableArray alloc] init];
    if(self.accounts.count > 1)
    {
        SLComposeSheetConfigurationItem* accountSelector = [[SLComposeSheetConfigurationItem alloc] init];
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
    {
        self.account = [self.accounts objectAtIndex:0];
    }
    SLComposeSheetConfigurationItem* recipient = [[SLComposeSheetConfigurationItem alloc] init];
    recipient.title = NSLocalizedString(@"Recipient", @"shareViewController: recipient");
    recipient.value = self.recipient.contactJid;
    recipient.tapHandler = ^{
        UIStoryboard* iosShareStoryboard = [UIStoryboard storyboardWithName:@"iosShare" bundle:nil];
        MLSelectionController* controller = (MLSelectionController *)[iosShareStoryboard instantiateViewControllerWithIdentifier:@"contacts"];

        // Create list of recipients for the selected account
        NSMutableArray<NSDictionary*>* recipientsToShow = [[NSMutableArray alloc] init];
        for (MLContact* contact in self.recipients)
        {
            // only show contacts from the selected account
            if([contact.accountId isEqualToString:[NSString stringWithFormat:@"%@", [self.account objectForKey:@"account_id"]]])
                [recipientsToShow addObject:@{@"contact": contact}];
        }

        controller.options = recipientsToShow;
        controller.completion = ^(NSDictionary* selectedRecipient)
        {
            MLContact* contact = [selectedRecipient objectForKey:@"contact"];
            if(contact) {
                self.recipient = contact;
            }
            else {
                self.recipient = nil;
            }
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

-(void) openMainApp:(NSString*) recipient
{
    NSURL* mainAppUrl = [NSURL URLWithString:@"monalOpen://"];
    [self openURL:mainAppUrl];
}

@end
