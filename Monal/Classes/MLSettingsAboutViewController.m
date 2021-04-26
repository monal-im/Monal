//
//  MLSettingsAboutViewController.m
//  Monal
//
//  Created by jimtsai (poormusic2001@gmail.com) on 2021/4/12.
//  Copyright © 2021 Monal.im. All rights reserved.
//

#import "MLSettingsAboutViewController.h"
#import "HelperTools.h"

@interface MLSettingsAboutViewController ()
@property (weak, nonatomic) IBOutlet UITextView *aboutVersion;

@end

@implementation MLSettingsAboutViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    NSString* versionTxt = [HelperTools appBuildVersionInfo];
    [self.aboutVersion setText:versionTxt];
    
    UITapGestureRecognizer* tapReCognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(copyTxt:)];
    [self.aboutVersion addGestureRecognizer:tapReCognizer];
    UIBarButtonItem* rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(close:)];
    self.navigationItem.rightBarButtonItem = rightBarButtonItem;
}

- (NSArray<UIKeyCommand *>*)keyCommands 
{
    return @[
        [UIKeyCommand keyCommandWithInput:UIKeyInputEscape modifierFlags:0 action:@selector(close:)]
    ];
}

-(void) close:(id)sender
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

-(void) copyTxt:(id)sender
{
    UIPasteboard *pasteBoard = UIPasteboard.generalPasteboard;
    pasteBoard.string = self.aboutVersion.text;
}

@end
