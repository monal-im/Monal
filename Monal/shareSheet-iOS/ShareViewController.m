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

#import <MapKit/MapKit.h>

@interface ShareViewController ()

@property (nonatomic, strong) NSDictionary* account;
@property (nonatomic, strong) NSString* recipient;

@property (nonatomic, strong) NSArray* accounts;
@property (nonatomic, strong) NSArray<MLContact*>* recipients;

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

-(void)viewDidLoad {
    [super viewDidLoad];
    [self.navigationController.navigationBar setTintColor:[UIColor whiteColor]];
    [self.navigationController.navigationBar setBackgroundColor:[UIColor monaldarkGreen]];
    self.navigationController.navigationItem.title = NSLocalizedString(@"Monal", @"");
}

- (void)presentationAnimationDidFinish {
    DDLogInfo(@"Monal ShareViewController presentationAnimationDidFinish");
    
    self.accounts = [[HelperTools defaultsDB] objectForKey:@"accounts"];
    NSData* recipientsData = [[HelperTools defaultsDB] objectForKey:@"recipients"];
    
    NSError* error;
    NSSet* objClasses = [NSSet setWithArray:@[[NSMutableArray class], [NSArray class], [NSMutableDictionary class], [NSDictionary class], [NSNumber class], [NSString class], [NSDate class], [NSObject class], [MLContact class]]];
    self.recipients = (NSArray<MLContact*>*)[NSKeyedUnarchiver unarchivedObjectOfClasses:objClasses fromData:recipientsData error:&error];
    if(error) {
        DDLogError(@"Monal ShareViewController: %@", error);
    }

    self.recipient = [[HelperTools defaultsDB] objectForKey:@"lastRecipient"];
    self.account = [[HelperTools defaultsDB] objectForKey:@"lastAccount"];
    [self reloadConfigurationItems];
}

- (BOOL)isContentValid {
    if(self.recipient.length > 0 && self.account != nil)
    return YES;
    else return NO;
}

- (void)didSelectPost {
    NSExtensionItem* item = self.extensionContext.inputItems.firstObject;
    DDLogVerbose(@"Attachments = %@", item.attachments);

    u_int32_t magicIdentifyer = 0;
    NSMutableDictionary<NSNumber*, NSItemProvider*>* magicIdentifyerDic = [[NSMutableDictionary alloc] init];

    for (NSItemProvider* provider in item.attachments)
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
    [payload setObject:self.account forKey:@"account"];
    [payload setObject:self.recipient forKey:@"recipient"];

    // use best matching providers
    if((magicIdentifyer & MagicMapKitItem) > 0) {
        // convert map item to geo:
        NSItemProvider* provider = [magicIdentifyerDic objectForKey:[NSNumber numberWithUnsignedInt:MagicMapKitItem]];
        [provider loadItemForTypeIdentifier:@"com.apple.mapkit.map-item" options:NULL completionHandler:^(NSData*  _Nullable item, NSError * _Null_unspecified error) {
            NSError* err;
            MKMapItem* mapItem = [NSKeyedUnarchiver unarchivedObjectOfClass:[MKMapItem class] fromData:item error:&err];
            DDLogWarn(@"%@", err);
            [payload setObject:[NSString stringWithFormat:@"geo:%f,%f", mapItem.placemark.coordinate.latitude, mapItem.placemark.coordinate.longitude] forKey:@"url"];
            if(self.contentText.length > 0)
            {
                [payload setObject:self.contentText forKey:@"comment"];
            }
            [self savePayloadMsgAndComplete:payload];
        }];
    }
    else if((magicIdentifyer & MagicPublicUrl) > 0)
    {
        NSItemProvider* provider = [magicIdentifyerDic objectForKey:[NSNumber numberWithUnsignedInt:MagicPublicUrl]];
        [provider loadItemForTypeIdentifier:@"public.url" options:NULL completionHandler:^(NSURL<NSSecureCoding>*  _Nullable item, NSError * _Null_unspecified error) {
            [payload setObject:item.absoluteString forKey:@"url"];
            if(self.contentText.length > 0)
            {
                [payload setObject:self.contentText forKey:@"comment"];
            }
            [self savePayloadMsgAndComplete:payload];
        }];
    }
    else if((magicIdentifyer & MagicPlainTxt) > 0)
    {
        if(self.contentText.length > 0)
        {
            [payload setObject:self.contentText forKey:@"comment"];
        }
        [self savePayloadMsgAndComplete:payload];
    }
}

-(void) savePayloadMsgAndComplete:(NSDictionary*) payload
{
    // append to old outbox
    NSMutableArray* outbox = [[[HelperTools defaultsDB] objectForKey:@"outbox"] mutableCopy];
    if(!outbox) outbox = [[NSMutableArray alloc] init];

    [outbox addObject:payload];
    [[HelperTools defaultsDB] setObject:outbox forKey:@"outbox"];

    // Save last used account / recipient
    [[HelperTools defaultsDB] setObject:self.account forKey:@"lastAccount"];
    [[HelperTools defaultsDB] setObject:self.recipient forKey:@"lastRecipient"];

    [[HelperTools defaultsDB] synchronize];

    [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
}

- (NSArray *)configurationItems {
    NSMutableArray *toreturn = [[NSMutableArray alloc] init];
    if(self.accounts.count > 1) {
        SLComposeSheetConfigurationItem* accountSelector = [[SLComposeSheetConfigurationItem alloc] init];
        accountSelector.title = NSLocalizedString(@"Account", @"ShareViewController: Account");

        accountSelector.value = [NSString stringWithFormat:@"%@@%@",[self.account objectForKey:@"username"],[self.account objectForKey:@"domain"]];
        accountSelector.tapHandler = ^{
            UIStoryboard* iosShareStoryboard = [UIStoryboard storyboardWithName:@"iosShare" bundle:nil];
            MLSelectionController* controller = (MLSelectionController*)[iosShareStoryboard instantiateViewControllerWithIdentifier:@"accounts"];
            controller.options= self.accounts;
            controller.completion = ^(NSDictionary *selectedAccount)
            {
                if(selectedAccount) {
                    self.account = selectedAccount;
                }
                else {
                    self.account = nil;
                }
                self.recipient = @"";
                [self reloadConfigurationItems];
            };
            
            [self pushConfigurationViewController:controller];
        };
        [toreturn addObject:accountSelector];
    }
    
    if(!self.account && self.accounts.count>0) {
        self.account = [self.accounts objectAtIndex:0];
        
    }
    
    SLComposeSheetConfigurationItem *recipient = [[SLComposeSheetConfigurationItem alloc] init];
    recipient.title = NSLocalizedString(@"Recipient", @"shareViewController: recipient");
    recipient.value = self.recipient;
    recipient.tapHandler = ^{
        UIStoryboard* iosShareStoryboard = [UIStoryboard storyboardWithName:@"iosShare" bundle:nil];
        MLSelectionController* controller = (MLSelectionController *)[iosShareStoryboard instantiateViewControllerWithIdentifier:@"contacts"];

        // Create list of recipients for the selected account
        NSMutableArray<NSDictionary*>* recipientsToShow = [[NSMutableArray alloc] init];
        for (MLContact* contact in self.recipients) {
            [recipientsToShow addObject:@{@"contact": contact}];
        }

        controller.options = recipientsToShow;
        controller.completion = ^(NSDictionary *selectedRecipient)
        {
            MLContact* contact = [selectedRecipient objectForKey:@"contact"];
            if(contact) {
                self.recipient = contact.contactJid;
            }
            else {
                self.recipient = @"";
            }
            [self reloadConfigurationItems];
        };
        
        [self pushConfigurationViewController:controller];
    };
    [toreturn addObject:recipient];
    [self validateContent];
    return toreturn;
}

@end
