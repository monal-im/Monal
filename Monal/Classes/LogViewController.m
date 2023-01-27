//
//  LogViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 12/20/13.
//
//

#import "LogViewController.h"
#import "MonalAppDelegate.h"
#import "HelperTools.h"
#import "DataLayer.h"
#import "MBProgressHUD.h"
#import "MLXMPPManager.h"
#import "MLUDPLogger.h"


@interface LogViewController ()
@property (weak, nonatomic) IBOutlet UITextField* logUDPHostname;
@property (weak, nonatomic) IBOutlet UITextField* logUDPPort;
@property (weak, nonatomic) IBOutlet UISwitch* logUDPSwitch;
@property (weak, nonatomic) IBOutlet UITextField* logUDPAESKey;
@property (nonatomic, strong) MBProgressHUD* hud;
@property (weak, nonatomic) IBOutlet UINavigationItem* navbar;

@end

@implementation LogViewController

DDLogFileInfo* _logInfo;

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
    
    self.logUDPHostname.delegate = self;
    self.logUDPPort.delegate = self;
    self.logUDPAESKey.delegate = self;
    
    UITapGestureRecognizer *tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(hideKeyboard)];
    [self.view addGestureRecognizer:tapGestureRecognizer];  
}

-(void) viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    NSArray* sortedLogFileInfos = [HelperTools.fileLogger.logFileManager sortedLogFileInfos];
    _logInfo = [sortedLogFileInfos objectAtIndex: 0];

    self.logUDPSwitch.on = [[HelperTools defaultsDB] boolForKey: @"udpLoggerEnabled"];
    self.logUDPPort.text = [[HelperTools defaultsDB] stringForKey: @"udpLoggerPort"];
    self.logUDPHostname.text = [[HelperTools defaultsDB] stringForKey: @"udpLoggerHostname"];
    self.logUDPAESKey.text = [[HelperTools defaultsDB] stringForKey:@"udpLoggerKey"];

    [self reloadLog];

    [self scrollToBottom];
}

-(void) viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    [[HelperTools defaultsDB] setBool:self.logUDPSwitch.on forKey:@"udpLoggerEnabled"];
    [[HelperTools defaultsDB] setObject:self.logUDPHostname.text forKey:@"udpLoggerHostname"];
    [[HelperTools defaultsDB] setObject:self.logUDPPort.text forKey:@"udpLoggerPort"];
    [[HelperTools defaultsDB] setObject:self.logUDPAESKey.text forKey:@"udpLoggerKey"];
    [[HelperTools defaultsDB] synchronize];
}

-(IBAction) sqliteExportAction:(id)sender {
    NSString* dbFile = [[DataLayer sharedInstance] exportDB];
    if(dbFile == nil)
        return;
    UIActivityViewController* shareController = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:dbFile]] applicationActivities:nil];
    shareController.popoverPresentationController.sourceView = self.view;
    [self presentViewController:shareController animated:YES completion:^{}];
}

-(IBAction) shareAction:(id)sender
{
    UIActivityViewController* shareController = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:_logInfo.filePath]] applicationActivities:nil];
    shareController.popoverPresentationController.sourceView = self.view;
    [self presentViewController:shareController animated:YES completion:^{}];
}

-(void) reloadLog {
    self.logView.text = NSLocalizedString(@"Only shareable for now", @"");    //[NSString stringWithContentsOfFile:_logInfo.filePath encoding:NSUTF8StringEncoding error:&error];
}

-(void) scrollToBottom {
    NSRange range = NSMakeRange(self.logView.text.length - 1, 1);
    [self.logView scrollRangeToVisible:range];
}

-(void) scrollToTop {
    NSRange range = NSMakeRange(0, 0);
    [self.logView scrollRangeToVisible:range];
}

/*
 * Toolbar button
 */

-(IBAction) rewindButton:(id)sender {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        [DDLog flushLog];
        [MLUDPLogger flushWithTimeout:0.100];
        $call($newHandler(self, IDontKwnowThis));
    });
}

-(IBAction) fastForwardButton:(id)sender {
    //[[NSArray arrayWithObject:@"object"] objectAtIndex:1];
    id delegate = NSClassFromString(@"MonalAppDelegate");
    SEL sel = NSSelectorFromString(@"UnknownSelectorExample");
    NSInvocation* inv = [NSInvocation invocationWithMethodSignature:[delegate methodSignatureForSelector:sel]];
    [inv setTarget:delegate];
    [inv setSelector:sel];
    [inv invoke];
}

-(IBAction) refreshButton:(id)sender {
    NSAssert(NO, @"assertion_example");
}

-(void) didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

-(BOOL) textFieldShouldReturn:(UITextField *)textField
{
    [textField resignFirstResponder];
    return YES;
}

-(void) hideKeyboard
{
    [self.view endEditing:YES];
}

-(IBAction) reconnect:(id) sender
{
    self.hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    self.hud.removeFromSuperViewOnHide = YES;
    self.hud.label.text = NSLocalizedString(@"Reconnecting", @"");
    self.hud.detailsLabel.text = NSLocalizedString(@"Will logout and reconnect any connected accounts.", @"");
    [[MLXMPPManager sharedInstance] reconnectAll];
    [self.hud hideAnimated:YES afterDelay:3.0f];
    self.hud = nil;
}

@end
