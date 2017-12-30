//
//  MLDisplaySettings.m
//  Monal
//
//  Created by Anurodh Pokharel on 7/29/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import "MLDisplaySettings.h"
#import "MLConstants.h"

@interface MLDisplaySettings ()

@end

@implementation MLDisplaySettings

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
}



-(void) viewWillAppear
{
    self.chatLogs.state = [[[NSUserDefaults standardUserDefaults] objectForKey:@"Logging"] boolValue];
    self.playSounds.state = [[[NSUserDefaults standardUserDefaults] objectForKey:@"Sound"] boolValue];
    
    self.showMessagePreview.state = [[[NSUserDefaults standardUserDefaults] objectForKey:@"MessagePreview"] boolValue];
    self.showOffline.state = [[[NSUserDefaults standardUserDefaults] objectForKey:@"OfflineContact"] boolValue];
    
    self.sortByStatus.state = [[[NSUserDefaults standardUserDefaults] objectForKey:@"SortContacts"] boolValue];
    self.showImages.state = [[NSUserDefaults standardUserDefaults] boolForKey: @"ShowImages"] ;
}


-(void) viewWillDisappear
{
    [[NSUserDefaults standardUserDefaults] setBool:self.chatLogs.state  forKey: @"Logging"];
    [[NSUserDefaults standardUserDefaults] setBool:self.playSounds.state  forKey: @"Sound"];
    
    [[NSUserDefaults standardUserDefaults] setBool:self.showMessagePreview.state  forKey: @"MessagePreview"];
    [[NSUserDefaults standardUserDefaults] setBool:self.showOffline.state  forKey: @"OfflineContact"];
    
    [[NSUserDefaults standardUserDefaults] setBool:self.sortByStatus.state  forKey: @"SortContacts"];
    [[NSUserDefaults standardUserDefaults] setBool:self.showImages.state  forKey: @"ShowImages"];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:kMonalRefreshContacts object:self];
    
}



#pragma mark - preferences delegate

- (NSString *)identifier
{
    return self.title;
}

- (NSImage *)toolbarItemImage
{
    return [NSImage imageNamed:@"1008-desktop"];
}

- (NSString *)toolbarItemLabel
{
    return @"Display";
}


@end
