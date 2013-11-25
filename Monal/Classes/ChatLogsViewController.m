//
//  ChatLogsViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/14/13.
//
//

#import "ChatLogsViewController.h"
#import "DataLayer.h"

@interface ChatLogsViewController ()

@end

@implementation ChatLogsViewController

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
    self.navigationItem.title=NSLocalizedString(@"Chat Logs",@"");
    self.view.backgroundColor=[UIColor lightGrayColor];
    self.view.autoresizingMask=UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleWidth;
    
    _chatLogTable=[[UITableView alloc] init];
    _chatLogTable.delegate=self;
    _chatLogTable.dataSource=self;
    
    self.view=_chatLogTable;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


-(void) viewWillAppear:(BOOL)animated
{
   // _tableData = [DataLayer sharedInstance];
}

#pragma mark tableview datasource delegate
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [_tableData count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return nil;
}


@end
