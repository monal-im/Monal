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

-(void) viewWillAppear
{
    self.away.state = [[[NSUserDefaults standardUserDefaults] objectForKey:@"Away"] boolValue];
    self.visibility.state = [[[NSUserDefaults standardUserDefaults] objectForKey:@"Visible"] boolValue];

    if([[NSUserDefaults standardUserDefaults] objectForKey:@"StatusMessage"]) {
        self.status.stringValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"StatusMessage"];
    }
    
    if( [[NSUserDefaults standardUserDefaults] objectForKey:@"XMPPPriority"]) {
        self.priority.stringValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"XMPPPriority"] ;
    }
    
}

-(void) viewWillDisappear
{
    if(![self.status.stringValue isEqualToString:[[NSUserDefaults standardUserDefaults] objectForKey:@"StatusMessage"]]) {
        [[MLXMPPManager sharedInstance] setStatusMessage:self.status.stringValue];
        [[NSUserDefaults standardUserDefaults] setObject:self.status.stringValue  forKey: @"StatusMessage"];
    }
    
    if(![self.priority.stringValue  isEqualToString:[[NSUserDefaults standardUserDefaults] objectForKey:@"XMPPPriority"]]) {
        [[NSUserDefaults standardUserDefaults] setObject:self.priority.stringValue  forKey: @"XMPPPriority"];
        [[MLXMPPManager sharedInstance] setPriority:[self.priority.stringValue  integerValue]];
    }
    
}

-(IBAction)toggleVisble:(id)sender
{
    [[MLXMPPManager sharedInstance] setVisible:self.visibility.state];
    [[NSUserDefaults standardUserDefaults] setBool:self.visibility.state  forKey: @"Visible"];
}

-(IBAction)toggleAway:(id)sender
{
    [[MLXMPPManager sharedInstance] setAway:self.away.state];
    [[NSUserDefaults standardUserDefaults] setBool:self.away.state  forKey: @"Away"];
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
