//
//  MLPlaceholderViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 1/5/20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import "MLPlaceholderViewController.h"

@interface MLPlaceholderViewController ()

@property (weak, nonatomic) IBOutlet UIImageView *backgroundImageView;

@end

@implementation MLPlaceholderViewController

- (void) viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    NSNotificationCenter* nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(handleBackgroundChanged) name:kMonalBackgroundChanged object:nil];
}


-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    self.splitViewController.preferredDisplayMode=UISplitViewControllerDisplayModeAllVisible;
    
    [self updateBackground:NO];
}

-(void) viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(void) handleBackgroundChanged
{
    [self updateBackground:YES];
}

-(void) updateBackground:(BOOL) forceReload
{
    BOOL backgrounds = [[HelperTools defaultsDB] boolForKey:@"ChatBackgrounds"];
    
    if(backgrounds == YES)
    {
        NSString* imageName = [[HelperTools defaultsDB] objectForKey:@"BackgroundImage"];
        if(imageName != nil)
        {
            if([imageName isEqualToString:@"CUSTOM"])
            {
                self.backgroundImageView.image = [[MLImageManager sharedInstance] getBackground:forceReload];
            }
            else
            {
                self.backgroundImageView.image = [UIImage imageNamed:imageName];
            }
        }
        else
        {
            self.backgroundImageView.image = nil;
        }
    }
    else
    {
        self.backgroundImageView.image = nil;
    }
}

@end
