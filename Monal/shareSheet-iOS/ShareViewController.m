//
//  ShareViewController.m
//  shareSheet
//
//  Created by Anurodh Pokharel on 9/10/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import "ShareViewController.h"
@import Crashlytics;
@import Fabric;

@interface ShareViewController ()

@end

@implementation ShareViewController

- (void)presentationAnimationDidFinish {
      [Fabric with:@[[Crashlytics class]]];
}

- (BOOL)isContentValid {
    // Do validation of contentText and/or NSExtensionContext attachments here
    return YES;
}

- (void)didSelectPost {
    // This is called after the user selects Post. Do the upload of contentText and/or NSExtensionContext attachments.
    
    //get text
    NSMutableDictionary *payload = [[NSMutableDictionary alloc] init];
    
    NSExtensionItem *item = self.extensionContext.inputItems.firstObject;
    NSLog(@"Attachments = %@", item.attachments);
    
    
    for (NSItemProvider *provider in item.attachments)
    {
       if([provider hasItemConformingToTypeIdentifier:@"public.url"])
       {
           [provider loadItemForTypeIdentifier:@"public.url" options:NULL completionHandler:^(NSURL<NSSecureCoding>*  _Nullable item, NSError * _Null_unspecified error) {
                [payload setObject:item.absoluteString forKey:@"url"];
                [payload setObject:self.contentText forKey:@"comment"];
               
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
    
    
    
    // Inform the host that we're done, so it un-blocks its UI. Note: Alternatively you could call super's -didSelectPost, which will similarly complete the extension context.
     [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
}

- (NSArray *)configurationItems {
    // To add configuration options via table cells at the bottom of the sheet, return an array of SLComposeSheetConfigurationItem here.
    SLComposeSheetConfigurationItem *account = [[SLComposeSheetConfigurationItem alloc] init];
    account.title=@"Account";
    account.value=@"anurodhp@jabb3r.org"; // last used
    SLComposeSheetConfigurationItem *recipient = [[SLComposeSheetConfigurationItem alloc] init];
    recipient.title=@"Recipient";
    recipient.value=@"monal2@jabb3r.org"; //last used
    
    return @[account, recipient];
}

@end
