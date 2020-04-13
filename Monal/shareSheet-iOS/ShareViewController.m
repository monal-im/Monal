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

@interface ShareViewController ()

@property (nonatomic, strong) NSDictionary *account;
@property (nonatomic, strong) NSString *recipient;

@property (nonatomic, strong) NSArray *accounts;
@property (nonatomic, strong) NSArray *recipients;


@end

@implementation ShareViewController

-(void)viewDidLoad {
    [super viewDidLoad];
    [self.navigationController.navigationBar setTintColor:[UIColor whiteColor]];
    [self.navigationController.navigationBar setBackgroundColor:[UIColor monaldarkGreen]];
    self.navigationController.navigationItem.title=@"Monal";
}

- (void)presentationAnimationDidFinish {
    NSUserDefaults *groupDefaults= [[NSUserDefaults alloc] initWithSuiteName:@"group.monal"];
    self.accounts= [groupDefaults objectForKey:@"accounts"];
    NSData *data=[groupDefaults objectForKey:@"recipients"];
    
    NSError *error;
    self.recipients=[NSKeyedUnarchiver unarchivedObjectOfClass:[NSArray class] fromData:data error:&error];
    
    self.recipient = [groupDefaults objectForKey:@"lastRecipient"];
    self.account = [groupDefaults objectForKey:@"lastAccount"];
    self.textView.text=@"";
    [self reloadConfigurationItems];
}

- (BOOL)isContentValid {
    if(self.recipient.length>0 && self.account!=nil)
    return YES;
    else return NO;
}

- (void)didSelectPost {
    NSMutableDictionary *payload = [[NSMutableDictionary alloc] init];
    
    NSExtensionItem *item = self.extensionContext.inputItems.firstObject;
   // NSLog(@"Attachments = %@", item.attachments);
    
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
               
                [groupDefaults setObject:self.account forKey:@"lastAccount"];
                [groupDefaults setObject:self.recipient forKey:@"lastRecipient"];
               
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
        account.value=[NSString stringWithFormat:@"%@@%@",[self.account objectForKey:@"username"],[self.account objectForKey:@"domain"]];
        account.tapHandler = ^{
            MLSelectionController *controller = (MLSelectionController *)[self.storyboard instantiateViewControllerWithIdentifier:@"accounts"];
            controller.options= self.accounts;
            controller.completion = ^(NSDictionary *selectedAccount)
            {
                if(selectedAccount) {
                    self.account=selectedAccount;
                }
                else {
                    self.account=nil;
                }
                self.recipient=@"";
                [self reloadConfigurationItems];
            };
            
            [self pushConfigurationViewController:controller];
        };
        [toreturn addObject:account];
    }
    
    if(!self.account && self.accounts.count>0) {
        self.account = [self.accounts objectAtIndex:0];
        
    }
    
    SLComposeSheetConfigurationItem *recipient = [[SLComposeSheetConfigurationItem alloc] init];
    recipient.title=@"Recipient";
    recipient.value=self.recipient;
    recipient.tapHandler = ^{
        MLSelectionController *controller = (MLSelectionController *)[self.storyboard instantiateViewControllerWithIdentifier:@"contacts"];
        
        NSMutableArray *recipientsToShow = [[NSMutableArray alloc] init];
        
        for (MLContact *row in self.recipients) {
            if([row.accountId integerValue]==[[self.account objectForKey:@"account_id"] integerValue])
            {
                [recipientsToShow addObject:@{@"contact":row}];
            }
        }
        
        controller.options = recipientsToShow;
        controller.completion = ^(NSDictionary *selectedRecipient)
        {
            MLContact *contact = [selectedRecipient objectForKey:@"contact"];
            if(contact) {
                self.recipient=contact.contactJid;
            }
            else {
                self.recipient=@"";
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
