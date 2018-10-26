//
//  ShareViewController.m
//  shareSheet
//
//  Created by Anurodh Pokharel on 9/10/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import "ShareViewController.h"
#import "MLSelectionController.h"
@import Crashlytics;
@import Fabric;

@interface ShareViewController ()

@property (nonatomic, strong) NSString *account;
@property (nonatomic, strong) NSString *recipient;

@property (nonatomic, strong) NSArray *accounts;
@property (nonatomic, strong) NSArray *recipients;


@end

@implementation ShareViewController

- (void)presentationAnimationDidFinish {
      [Fabric with:@[[Crashlytics class]]];
}

- (BOOL)isContentValid {

    if(self.recipient.length>0 && self.account.length>0)
    return YES;
    else return NO;
}

- (void)didSelectPost {
    NSMutableDictionary *payload = [[NSMutableDictionary alloc] init];
    
    NSExtensionItem *item = self.extensionContext.inputItems.firstObject;
    NSLog(@"Attachments = %@", item.attachments);
    
    for (NSItemProvider *provider in item.attachments)
    {
       if([provider hasItemConformingToTypeIdentifier:@"public.url"])
       {
           [provider loadItemForTypeIdentifier:@"public.url" options:NULL completionHandler:^(NSURL<NSSecureCoding>*  _Nullable item, NSError * _Null_unspecified error) {
               [payload setObject:item.absoluteString forKey:@"url"];
               if(self.contentText) [payload setObject:self.contentText forKey:@"comment"];
               [payload setObject:self.account forKey:@"account"];
               [payload setObject:self.recipient forKey:@"recipient"];
               
               NSUserDefaults *groupDefaults= [[NSUserDefaults alloc] initWithSuiteName:@"group.monal"];
               NSMutableArray *outbox=[[groupDefaults objectForKey:@"outbox"] mutableCopy];
               if(!outbox) outbox =[[NSMutableArray alloc] init];
               
               [outbox addObject:payload];
               [groupDefaults setObject:outbox forKey:@"outbox"];
               [groupDefaults synchronize];
           }];
       }
    }
    
    
//    [[[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:@"https://monal.im/wakeios"] completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
//
//
//    }] resume];

     [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
}

- (NSArray *)configurationItems {
    NSMutableArray *toreturn = [[NSMutableArray alloc] init];
    if(self.accounts.count>1) {
        SLComposeSheetConfigurationItem *account = [[SLComposeSheetConfigurationItem alloc] init];
        account.title=@"Account";
        account.value=self.account;
        account.tapHandler = ^{
            MLSelectionController *controller = (MLSelectionController *)[self.storyboard instantiateViewControllerWithIdentifier:@"accounts"];
            controller.completion = ^(NSString *selectedAccount)
            {
                if(selectedAccount) {
                    self.account=selectedAccount;
                }
                else {
                    self.account=@"";
                }
                [self reloadInputViews];
            };
            
            [self pushConfigurationViewController:controller];
        };
        [toreturn addObject:account];
    }
    
    SLComposeSheetConfigurationItem *recipient = [[SLComposeSheetConfigurationItem alloc] init];
    recipient.title=@"Recipient";
    recipient.value=self.recipient;
    recipient.tapHandler = ^{
        MLSelectionController *controller = (MLSelectionController *)[self.storyboard instantiateViewControllerWithIdentifier:@"contacts"];
        controller.completion = ^(NSString *selectedRecipient)
        {
            if(selectedRecipient) {
                self.recipient=selectedRecipient;
            }
            else {
                self.recipient=@"";
            }
            [self reloadInputViews];
        };
        
        [self pushConfigurationViewController:controller];
    };
    [toreturn addObject:recipient];
    
    return toreturn;
}

@end
