//
//  MLResourcesTableViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 12/30/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import "MLResourcesTableViewController.h"
#import "DataLayer.h"
#import "MLXMPPManager.h"
#import "MLContactSoftwareVersionInfo.h"

@interface MLResourcesTableViewController ()
@property (nonatomic, strong) NSArray *resources;
@property (nonatomic, strong) NSMutableDictionary *versionInfoDic;
@end

@implementation MLResourcesTableViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    if(self.contact.isGroup) {
        self.navigationItem.title=NSLocalizedString(@"Participants",@ "");
    } else {
        self.navigationItem.title=NSLocalizedString(@"Resources",@ "");
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshSoftwareVersion:) name: kMonalXmppUserSoftWareVersionRefresh object:nil];
        if (!self.versionInfoDic)
        {
            self.versionInfoDic = [[NSMutableDictionary alloc] init];
        }
    }    
}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    self.resources = [[DataLayer sharedInstance] resourcesForContact:self.contact];
    
    if (!self.contact.isGroup) {
        [self querySoftwareVersion];
        [self refreshSoftwareVersion:nil];
    }
}

-(void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    if(!self.contact.isGroup)
    {
        [[NSNotificationCenter defaultCenter] removeObserver:kMonalXmppUserSoftWareVersionRefresh];
    }
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if(!self.contact.isGroup)
    {
        return self.resources.count;
    }
    else
    {
        return 1;
    }    
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if(!self.contact.isGroup)
    {
        return 3;
    }
    else
    {
        return self.resources.count;
    }
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if(section>=self.resources.count) {
        return @"";
    }
    NSString* resourceTitle = [[self.resources objectAtIndex:section] objectForKey:@"resource"];
    return  resourceTitle;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"resource" forIndexPath:indexPath];
    
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    if (self.contact.isGroup)
    {
        cell.textLabel.text = [[self.resources objectAtIndex:indexPath.row] objectForKey:@"resource"];
    }
    else
    {
        NSString* resourceTitle = [[self.resources objectAtIndex:indexPath.section] objectForKey:@"resource"];
        if (resourceTitle)
        {
            NSDictionary* versionDataDictionary = [self.versionInfoDic objectForKey:resourceTitle];
            
            switch (indexPath.row) {
                case 0:
                    cell.textLabel.text = [NSString stringWithFormat:@"%@%@",
                                              NSLocalizedString(@"Name: ", @""),
                                              (versionDataDictionary[@"platform_App_Name"] == nil) ? @"":versionDataDictionary[@"platform_App_Name"]];
                    break;
                case 1:
                    cell.textLabel.text = [NSString stringWithFormat:@"%@%@",
                                              NSLocalizedString(@"Os: ", @""),
                                              (versionDataDictionary[@"platform_OS"] == nil) ? @"":versionDataDictionary[@"platform_OS"]];
                    break;
                case 2:
                    cell.textLabel.text = [NSString stringWithFormat:@"%@%@",
                                              NSLocalizedString(@"Version: ", @""),
                                              (versionDataDictionary[@"platform_App_Version"] == nil) ? @"":versionDataDictionary[@"platform_App_Version"]];
                    break;
                default:
                    break;
            }
        }
    }
    
    return cell;
}

#pragma mark - Query Software Version

-(void) querySoftwareVersion
{
    for (NSDictionary* resourceDic in self.resources)
    {
        NSString* resourceTitle = [resourceDic objectForKey:@"resource"];
        [[MLXMPPManager sharedInstance] getEntitySoftWareVersionForContact:self.contact andResource:resourceTitle];
    }
}

#pragma mark - refresh software version
-(void) refreshSoftwareVersion:(NSNotification*) verNotification
{
    if (verNotification) {
        NSMutableDictionary* inVerDictionary = [verNotification.userInfo mutableCopy];
        NSString* resourceKey = [inVerDictionary objectForKey:@"fromResource"];
        if (resourceKey)
        {
            [inVerDictionary removeObjectForKey:@"fromResource"];
            [self.versionInfoDic setObject:inVerDictionary forKey:resourceKey];
        }
    } else {
        for (NSDictionary* resourceDic in self.resources)
        {
            NSString* resourceTitle = [resourceDic objectForKey:@"resource"];
            MLContactSoftwareVersionInfo* versionDBInfo = [[DataLayer sharedInstance] getSoftwareVersionInfoForContact:self.contact.contactJid resource:resourceTitle andAccount:self.contact.accountId];
            if(versionDBInfo != nil) {
                [self.versionInfoDic setObject:versionDBInfo forKey:resourceTitle];
            }
        }
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
    });
}
@end
