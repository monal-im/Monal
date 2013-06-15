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
    self.navigationController.navigationBarHidden=NO;

    CGRect viewFrame = CGRectMake(0, 0, 80, [[UIScreen mainScreen] bounds].size.height);
    self.view= [[UIView alloc] initWithFrame:viewFrame];
    self.view.backgroundColor=[UIColor lightGrayColor];
    self.view.autoresizingMask=UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleWidth;
    
    
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
