//
//  MLAccountSettings.m
//  Monal
//
//  Created by Anurodh Pokharel on 7/29/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import "MLAccountSettings.h"
#import "MLAccountRow.h"
#import "MLAccountEdit.h"
#import "DataLayer.h"

@interface MLAccountSettings ()
@property (nonatomic, strong) NSArray *accountList;

@end

@implementation MLAccountSettings

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
    
}

-(void) viewWillAppear
{
    self.accountList=[[DataLayer sharedInstance] accountList];
    [self.accountTable reloadData];
}



-(IBAction)deleteAccount:(id)sender
{
    //get selected.
    
    NSInteger selected = [self.accountTable selectedRow];
    if(selected < self.accountList.count) {
        NSDictionary * row = [self.accountList objectAtIndex:selected];
        
        // pass to database
        NSString *accountID = [row objectForKey:kAccountID];
        [[DataLayer sharedInstance] removeAccount:accountID];
        
        // update display
        [self.accountTable noteNumberOfRowsChanged];
    }
}

#pragma mark -- segues

-(IBAction)showXMPP:(id)sender {
    [self performSegueWithIdentifier:@"showAccountEdit" sender:@"XMPP"];
}

-(IBAction)showGtalk:(id)sender {
     [self performSegueWithIdentifier:@"showAccountEdit" sender:@"Gtalk"];
}

- (void)prepareForSegue:(NSStoryboardSegue *)segue sender:(id)sender
{
    MLAccountEdit *sheet = (MLAccountEdit *)[segue destinationController];
    
    if([sender isEqualToString:@"Gtalk"])
    {
        sheet.server.stringValue= @"talk.google.com";
        sheet.jabberID.stringValue=@"@gmail.com";
    }
    
}


#pragma mark  -- tableview datasource
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView;
{
    return self.accountList.count;
}


#pragma  mark -- tableview delegate
- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row;
{
    MLAccountRow *tableRow = [tableView makeViewWithIdentifier:@"AccountRow" owner:nil];
    
    NSDictionary *account = [self.accountList objectAtIndex:row];
    [tableRow updateWithAccountDictionary:account];
    
    return tableRow;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification;
{
    
}

#pragma mark - preferences delegate

- (NSString *)identifier
{
    return self.title;
}

- (NSImage *)toolbarItemImage
{
    return [NSImage imageNamed:NSImageNameAdvanced];
}

- (NSString *)toolbarItemLabel
{
    return @"";
}


@end
