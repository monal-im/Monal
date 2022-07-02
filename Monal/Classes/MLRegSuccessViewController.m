//
//  MLRegSuccessViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/3/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import "MLRegSuccessViewController.h"
#import "HelperTools.h"

@interface MLRegSuccessViewController ()

@end

@implementation MLRegSuccessViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    //set QR code
    self.jid.text = self.registeredAccount; 
}

-(IBAction) close:(id) sender
{
    //call completion handler if given (e.g. add contact and open chatview)
    if(self.completionHandler)
    {
        DDLogVerbose(@"Calling reg completion handler...");
        self.completionHandler();
    }
    
    // open privacy settings after 1 second
    //(if we directly segue to an open chat, this will be done after 0.5 seconds,
    //waiting 1 second makes sure the privacy settings will still be opened while
    //the open chat lies one ui layer beneath it and can be used as soon as sthe privacy settings get dismissed)
    createQueuedTimer(1.0, dispatch_get_main_queue(), (^{
        if(![[HelperTools defaultsDB] boolForKey:@"HasSeenPrivacySettings"]) {
            [self performSegueWithIdentifier:@"showPrivacySettings" sender:self];
            return;
        }
    }));
    [self dismissViewControllerAnimated:YES completion:nil];
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
