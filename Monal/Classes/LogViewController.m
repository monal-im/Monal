//
//  LogViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 12/20/13.
//
//

#import "LogViewController.h"
#import "MonalAppDelegate.h"


@interface LogViewController ()

@end

@implementation LogViewController

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
}

-(void) viewDidAppear:(BOOL)animated
{
    
    
    MonalAppDelegate* appDelegate= (MonalAppDelegate*) [UIApplication sharedApplication].delegate;
    DDFileLogger *logger=appDelegate.fileLogger;
    
    NSArray *sortedLogFileInfos = [logger.logFileManager sortedLogFileInfos];
    DDLogFileInfo *logFileInfo = [sortedLogFileInfos objectAtIndex: [sortedLogFileInfos count]-1];
    NSError *error;
    self.logView.text=[NSString stringWithContentsOfFile:logFileInfo.filePath encoding:NSUTF8StringEncoding error:&error];
    
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
