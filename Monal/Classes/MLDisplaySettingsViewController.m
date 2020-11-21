//
//  SettingsViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/14/13.
//
//

#import "HelperTools.h"
#import "MLDisplaySettingsViewController.h"
#import "MLConstants.h"
#import "DataLayer.h"


@interface MLDisplaySettingsViewController ()

@end

@implementation MLDisplaySettingsViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.
    self.navigationItem.title = NSLocalizedString(@"Display Settings",@"");
   
    _settingsTable = self.tableView;
    _settingsTable.delegate = self;
    _settingsTable.dataSource = self;
    _settingsTable.backgroundView = nil;
}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
}

-(void) viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [[HelperTools defaultsDB] synchronize];
    
    //update logs if needed
    if(! [[HelperTools defaultsDB] boolForKey:@"Logging"])
    {
        [[DataLayer sharedInstance] messageHistoryCleanAll];
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark tableview datasource delegate
-(NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 3;
}


-(UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    NSString* sectionTitle = [self tableView:tableView titleForHeaderInSection:section];
    return [HelperTools MLCustomViewHeaderWithTitle:sectionTitle];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    switch (section) {
        case 0:
        {
            return NSLocalizedString(@"Status", @"");
            break;
        }
        case 1:
        {
            return NSLocalizedString(@"Presence", @"");
            break;
        }
        case 2:
        {
            return NSLocalizedString(@"General", @"");
            break;
        }
        default:
        {
            return nil;
            break;
        }
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch (section) {
        case 0:
        {
            return 1;
            break;
        }
        case 1:
        {
            return 1;
            break;
        }
        case 2:
        {
            return 4;
            break;
        }
        default:
        {
            return 0; 
        }
        break;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    
    MLSettingCell* cell = [[MLSettingCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"AccountCell"];
    cell.parent = self;
   
    switch (indexPath.section) {
        case 0:
        {
            switch(indexPath.row)
            {
                case 0:
                {
                    cell.textInputField.placeholder=NSLocalizedString(@"Status Message", @"");
                    cell.textInputField.keyboardType=UIKeyboardTypeAlphabet;
                    cell.defaultKey=@"StatusMessage";
                    cell.textEnabled=YES;
                    return cell;
                }
            }
        }
        
        case 1:
        {
            switch(indexPath.row)
            {
                case 0:
                {
                    cell.textLabel.text=NSLocalizedString(@"Away", @"");
                    cell.defaultKey=@"Away";
                    cell.switchEnabled=YES;
                    break;
                }  
            }
            return cell; 
        }
        
        case 2:
        {
            switch(indexPath.row)
            {
                case 0:
                {
                    cell.textLabel.text=NSLocalizedString(@"Message Preview", @"");
                    cell.defaultKey=@"MessagePreview";
                    cell.switchEnabled=YES;
                    break; 
                }
                case 1:
                {
                    cell.textLabel.text=NSLocalizedString(@"Log Chats", @"");
                    cell.defaultKey=@"Logging";
                    cell.switchEnabled=YES;
                    break;
                }
                case 2:
                {
                    cell.textLabel.text = NSLocalizedString(@"Offline Contacts", @"");
                       cell.defaultKey = @"OfflineContact";
                    cell.switchEnabled = YES;
                    break;
                }
                case 3:
                {
                    cell.textLabel.text = NSLocalizedString(@"Sort By Status", @"");
                       cell.defaultKey = @"SortContacts";
                    cell.switchEnabled = YES;
                    break;
                }
            }
            return cell; 
        }
    }
}

-(IBAction)close:(id)sender
{
    [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

@end
