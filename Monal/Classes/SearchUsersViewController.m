//
//  SearchUsersViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/14/13.
//
//

#import "SearchUsersViewController.h"
#import "MLConstants.h"

@interface SearchUsersViewController ()

@end

@implementation SearchUsersViewController

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
    self.navigationItem.title=NSLocalizedString(@"Search Users",@"");
    if(SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7.0"))
    {
        
    }
    else
    {
        [self.view setBackgroundColor:[UIColor colorWithPatternImage:[UIImage imageNamed:@"debut_dark"]]];
    }
    self.view.autoresizingMask=UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleWidth;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
