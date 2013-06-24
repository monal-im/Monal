//
//  ContactsViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/14/13.
//
//

#import "ContactsViewController.h"

@interface ContactsViewController ()

@end

@implementation ContactsViewController

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
    // Do any additional setup after loading the view from its nib.
    self.navigationItem.title=NSLocalizedString(@"Contacts",@"");
    self.view.backgroundColor=[UIColor lightGrayColor];
    self.view.autoresizingMask=UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleWidth;
   
    _contactsTable=[[UITableView alloc] init];
    _contactsTable.delegate=self;
    _contactsTable.dataSource=self;
    
    self.view=_contactsTable;
    
    
    
}

-(void) viewWillAppear:(BOOL)animated
{
    
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark tableview datasource delegate
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return 0; 
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return nil;
}

@end
