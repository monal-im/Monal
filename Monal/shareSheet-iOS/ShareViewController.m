//
//  ShareViewController.m
//  shareSheet
//
//  Created by Anurodh Pokharel on 9/10/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import "ShareViewController.h"
#import "MLSelectionController.h"
#import "GeneratedAssetSymbols.h"

#import <monalxmpp/MLContact.h>
#import <monalxmpp/MLConstants.h>
#import <monalxmpp/HelperTools.h>
#import <monalxmpp/DataLayer.h>
#import <monalxmpp/MLFileTransfer.h>
#import <monalxmpp/IPC.h>

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
    
    //resume logging and other core tasks
    [HelperTools signalResumption];
    
    //init IPC
    [IPC initializeForProcess:@"ShareSheetExtension"];
    
    //log startup
    DDLogInfo(@"Share Sheet Extension started: %@", [HelperTools appBuildVersionInfoFor:MLVersionTypeLog]);
    [DDLog flushLog];
    
    MLAssert([HelperTools deviceUUIDAccessibleOrAllowedEmpty:YES] == YES, @"device UUID should always be accessible or empty when using the share extension!");
}

-(void) viewDidLoad
{
    [super viewDidLoad];
    [self.navigationController.navigationBar setTintColor:UIColor.systemBackgroundColor];
    [self.navigationController.navigationBar setBackgroundColor:[UIColor colorNamed:ACColorNameMonalGreen]];
    self.navigationController.navigationItem.title = NSLocalizedString(@"Monal", @"");
    
    DDLogInfo(@"Extension context: %@", self.extensionContext);
    DDLogDebug(@"Raw extension context intent: %@", self.extensionContext.intent);
    if(self.extensionContext.intent != nil && [self.extensionContext.intent isKindOfClass:[INSendMessageIntent class]])
    {
        INSendMessageIntent* intent = (INSendMessageIntent*)self.extensionContext.intent;
        DDLogDebug(@"Got usable intent: %@", intent);
        self.intentContact = [HelperTools unserializeData:[intent.conversationIdentifier dataUsingEncoding:NSISOLatin1StringEncoding]];
        DDLogInfo(@"Extracted intent contact: %@", self.intentContact);
        [self.intentContact refresh];       //make sure we are up to date
    }
}

- (void) presentationAnimationDidFinish
{
    // list all contacts, not only active chats
    // that will clutter the list of selectable contacts, but you can always use sirikit interactions
    // to get the recently used contacts listed
    NSArray<MLContact*>* allContacts = [[DataLayer sharedInstance] contactList];
    NSMutableArray<MLContact*>* contactsToDisplay = [NSMutableArray new];
    //ignore all contacts not at least in any roster state: e.g. subscribedTo or asking state
    //OR is subscribedFrom (e.g. we approved them already, but they don't approve us)
    //order pinned before unpinned ones
    for(MLContact* contact in allContacts)
        if(((contact.isSubscribedTo || contact.hasOutgoingContactRequest) || contact.isSubscribedFrom) && contact.isPinned)
            [contactsToDisplay addObject:contact];
    for(MLContact* contact in allContacts)
        if(((contact.isSubscribedTo || contact.hasOutgoingContactRequest) || contact.isSubscribedFrom) && !contact.isPinned)
            [contactsToDisplay addObject:contact];
    self.recipients = [contactsToDisplay copy];
    self.accounts = [[DataLayer sharedInstance] enabledAccountList];

    if(self.intentContact != nil)
    {
        DDLogInfo(@"Intent contact given: %@", self.intentContact);
        //check if intentContact is in enabled account list
        for(NSDictionary* accountToCheck in self.accounts)
        {
            NSNumber* accountID = [accountToCheck objectForKey:@"account_id"];
            if(accountID.intValue == self.intentContact.accountID.intValue)
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
        DDLogInfo(@"No recipient given, selecting the one with the most recent interaction...");
        BOOL recipientFound = NO;
        for(MLContact* recipient in self.recipients)
        {
            for(NSDictionary* accountToCheck in self.accounts)
            {
                NSNumber* accountID = [accountToCheck objectForKey:@"account_id"];
                if(accountID.intValue == recipient.accountID.intValue)
                {
                    self.recipient = recipient;
                    self.account = accountToCheck;
                    recipientFound = YES;
                    break;
                }
            }
            if(recipientFound == YES)
                break;
        }
    }
    
    [self reloadConfigurationItems];
}

-(MLContact* _Nullable) getLastContactForAccount:(NSNumber*) accountID
{
    for(MLContact* recipient in self.recipients) {
        if(recipient.accountID.intValue == accountID.intValue) {
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

-(NSExtensionItem*) filterItems:(NSArray*) items
{
    for(NSExtensionItem* item in items)
        for(NSItemProvider* provider in item.attachments)
        {
            //public.data, public.file-url, or com.apple.pkpass
            if([provider hasItemConformingToTypeIdentifier:UTTypeData.identifier])
                return item;
            else if([provider hasItemConformingToTypeIdentifier:UTTypeFileURL.identifier])
                return item;
            else if([provider hasItemConformingToTypeIdentifier:@"com.apple.pkpass"])
                return item;
        }
    return items.firstObject;       //fallback, should normally not be needed
}

-(void) didSelectPost
{
    DDLogVerbose(@"input items: %@", self.extensionContext.inputItems);
    
    //filter items for first one matching public.data, public.file-url, or com.apple.pkpass (Signal does the same)
    //TODO: should we instead simply flatten all attachments of all items into one attachments array instead, like other apps seem to do it?
    NSExtensionItem* item = [self filterItems:self.extensionContext.inputItems];
    
    //convert all attachments to fulfilled promises
    DDLogVerbose(@"Attachments = %@", item.attachments);

    //process all items first (tmpfiles of unused ones will be autodeleted by our tmpfile cleanup)
    NSMutableArray<AnyPromise*>* attachments = [NSMutableArray new];
    for(NSItemProvider* provider in item.attachments)
        //extract item data
        [attachments addObject:[AnyPromise promiseWithValue:provider].then(^id(NSItemProvider* provider) {
            DDLogDebug(@"Handling: %@", provider);
            return [HelperTools handleUploadItemProvider:provider].then(^id(NSMutableDictionary* payload) {
                return PMKManifold(provider, payload);
            });
        //add recipient information
        }).then(^id(NSItemProvider* provider, NSMutableDictionary* payload) {
            DDLogDebug(@"Got handleUploadItemProvider callback with payload: %@ for provider: %@", payload, provider);
            if(payload == nil)      //short circuit
                return nil;
            payload[@"account_id"] = self.recipient.accountID;
            payload[@"recipient"] = self.recipient.contactJid;
            return PMKManifold(provider, payload);
        //filter out all bplist items already contained in the contentText field (google youtube and google maps apps)
        }).then(^id(NSItemProvider* provider, NSDictionary* payload) {
            if(payload == nil)      //short circuit
                return nil;
            
            //text shares (not text files) are often also shared via comment field
            //--> special handling below, everything else is just returned
            //(we have to check if we landed in the last text file block inside handleUploadItemProvider,
            //because hasItemConformingToTypeIdentifier would also match for UTTypeURL etc.)
            if(![payload[@"uttype"] isEqualToString:UTTypePlainText.identifier])
                return payload;
            
            //ignore text shares, if they contain the same contents as the comment field
            if(self.contentText && [self.contentText length] > 0 && [payload[@"data"] isKindOfClass:[NSString class]] && [self.contentText isEqualToString:payload[@"data"]])
            {
                DDLogWarn(@"Ignoring plain text payload because already sent via comment field");
                return nil;
            }
            
            //urls or other plaintext transfered as bplist
            return [AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
                [provider loadItemForTypeIdentifier:UTTypePlainText.identifier options:nil completionHandler:^(NSString*  _Nullable item, NSError* _Null_unspecified error) {
                    if(self.contentText && [self.contentText length] > 0 && item != nil && [self.contentText isEqualToString:item])
                    {
                        DDLogWarn(@"Ignoring serialized text payload because already sent via comment field");
                        resolve(nil);
                    }
                    else
                        resolve(payload);
                }];
            }];
        })];
    
    //make sure we only process non-nil payloads
    PMKWhen(attachments).then(^id(NSArray* payloads) {
        return arrayComprehension(payloads, ^id(id e) { return nilExtractor(e); });
    //finally filter for attachments we really want (signalapp style)
    }).then(^id(NSArray* payloads) {
        uint32_t saved = 0;
        NSMutableSet<NSString*>* uttypes = [NSMutableSet new];
        for(NSDictionary* payload in payloads)
            [uttypes addObject:payload[@"uttype"]];
        
        //add the contentText as normal message payload, if given
        if(self.contentText && [self.contentText length] > 0)
        {
            DDLogInfo(@"Adding contentText as text message...");
            NSMutableDictionary* payload = [NSMutableDictionary new];
            payload[@"account_id"] = self.recipient.accountID;
            payload[@"recipient"] = self.recipient.contactJid;
            payload[@"type"] = @"text";
            payload[@"data"] = self.contentText;
            DDLogDebug(@"Adding shareSheet comment payload: %@", payload);
            [[DataLayer sharedInstance] addShareSheetPayload:payload];
            saved++;
        }
        
        //mapkit items are superior above all others (urls, files, text): ignore everything else
        if([uttypes containsObject:@"com.apple.mapkit.map-item"])
        {
            for(NSDictionary* payload in payloads)
                if(payload[@"error"] == nil && [payload[@"uttype"] isEqualToString:@"com.apple.mapkit.map-item"])
                {
                    DDLogInfo(@"Adding geo special shareSheet payload(%u): %@", saved, payload);
                    [[DataLayer sharedInstance] addShareSheetPayload:payload];
                    saved++;
                    return PMKManifold(@(saved), @[]);     //empty list --> no error handling (we extracted the map item, thats all we need)
                }
        }
        //contacts are also special: ignore everything else
        if([uttypes containsObject:UTTypeContact.identifier])
        {
            for(NSDictionary* payload in payloads)
                if(payload[@"error"] == nil && [payload[@"uttype"] isEqualToString:UTTypeContact.identifier])
                {
                    DDLogInfo(@"Adding contact special shareSheet payload(%u): %@", saved, payload);
                    [[DataLayer sharedInstance] addShareSheetPayload:payload];
                    saved++;
                    return PMKManifold(@(saved), @[]);     //empty list --> no error handling (we extracted the map item, thats all we need)
                }
        }
        
        //try to use all files (images, videos, simple files)...
        for(NSDictionary* payload in payloads)
            if(payload[@"error"] == nil && ([payload[@"type"] isEqualToString:@"image"] || [payload[@"type"] isEqualToString:@"file"] || [payload[@"type"] isEqualToString:@"audiovisual"]))
            {
                DDLogInfo(@"Adding %@ shareSheet payload(%u): %@", payload[@"type"], saved, payload);
                [[DataLayer sharedInstance] addShareSheetPayload:payload];
                saved++;
            }
//         //...and additionally use urls if no files were found...
//         if(saved == 0)
        //...and additionally use urls...
        if(YES)
        {
            for(NSDictionary* payload in payloads)
                if(payload[@"error"] == nil && [payload[@"type"] isEqualToString:@"url"])
                {
                    DDLogInfo(@"Adding %@ shareSheet payload(%u): %@", payload[@"type"], saved, payload);
                    [[DataLayer sharedInstance] addShareSheetPayload:payload];
                    saved++;
                    break;          //use only the first url
                }
        }
        //...finally simply use everything provided, if neither a file nor url could be found
        if(saved == 0)
        {
            for(NSDictionary* payload in payloads)
            {
                DDLogInfo(@"Adding any (%@) shareSheet payload(%u): %@", payload[@"type"], saved, payload);
                [[DataLayer sharedInstance] addShareSheetPayload:payload];
                saved++;
            }
        }
        
        //return saved payload count and full payload list to next stage for error handling
        return PMKManifold(@(saved), payloads);
    //extract all errors and warn the user about it, this resolves once the user dismisses the error
    }).then(^id(NSNumber* saved, NSArray* payloads) {
        return [AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
            //extract error descriptions
            NSArray* errorTexts = arrayComprehension(payloads, ^id(NSDictionary* payload) {
                if(payload[@"error"] == nil)
                    return nil;
                DDLogError(@"Could not save payload for sending: %@", payload);
                return [payload[@"error"] localizedDescription];
            });
            
            if(errorTexts.count == 0)
                return resolve(saved);
            
            //build alert message
            NSString* message = [NSString stringWithFormat:NSLocalizedString(@"Monal was not able to send any of your attachments: %@", @""), errorTexts];
            if(saved.unsignedIntValue > 0)
                message = [NSString stringWithFormat:NSLocalizedString(@"Monal was not able to send some of your attachments: %@", @""), errorTexts];
            
            UIAlertController* unknownItemWarning = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Could not send", @"")
                                                                        message:message preferredStyle:UIAlertControllerStyleAlert];
            [unknownItemWarning addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Dismiss", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
                [unknownItemWarning dismissViewControllerAnimated:YES completion:^{
                    resolve(saved);
                }];
            }]];
            [self presentViewController:unknownItemWarning animated:YES completion:nil];
        }];
    //then open the mainapp if we actually managed to extract anything sendable
    }).then(^(NSNumber* saved) {
        DDLogInfo(@"Got %@ saved share items, opening the main app now...", saved);
        [self.extensionContext completeRequestReturningItems:@[] completionHandler:^(BOOL expired __unused) {
            if(saved.unsignedIntValue > 0)
                [self openMainApp];
            [HelperTools signalSuspension];
            //make sure the next start of this extension is a fresh one (like we already do with the NSE appex)
            createTimer(0.250, (^{
                DDLogInfo(@"Committing suicide...");
                exit(0);
            }));
        }];
    });
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
            NSNumber* accountID = [self.account objectForKey:@"account_id"];
            if(contact.accountID.intValue == accountID.intValue)
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
                [app openURL:url options:@{} completionHandler:nil];
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
