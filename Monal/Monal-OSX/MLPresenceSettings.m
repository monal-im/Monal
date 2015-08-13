//
//  MLPresenceSettings.m
//  Monal
//
//  Created by Anurodh Pokharel on 7/29/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import "MLPresenceSettings.h"
#import "MLXMPPManager.h"

@interface MLPresenceSettings ()

@end

@implementation MLPresenceSettings


- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
}

-(void) viewDidAppear
{
    self.away.state = [[[NSUserDefaults standardUserDefaults] objectForKey:@"Away"] boolValue];
    self.visibility.state = [[[NSUserDefaults standardUserDefaults] objectForKey:@"Visible"] boolValue];
}


-(void) viewWillDisappear
{
    [[NSUserDefaults standardUserDefaults] setBool:self.away.state  forKey: @"Away"];
    [[NSUserDefaults standardUserDefaults] setBool:self.visibility.state  forKey: @"Visible"];
}

#pragma mark - preferences delegate

- (NSString *)identifier
{
    return self.title;
}

- (NSImage *)toolbarItemImage
{
    return [NSImage imageNamed:@"740-gear"];
}

- (NSString *)toolbarItemLabel
{
    return @"Presence";
}


@end
