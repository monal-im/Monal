//
//  MLCloudStorageSettings.m
//  Monal
//
//  Created by Anurodh Pokharel on 2/25/16.
//  Copyright © 2016 Monal.im. All rights reserved.
//

#import "MLCloudStorageSettings.h"
#import <DropBoxOSX/DropBoxOSX.h>

@interface MLCloudStorageSettings ()

@end

@implementation MLCloudStorageSettings

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
}

-(void) viewWillAppear
{
    self.dropBox.state= [DBSession sharedSession].isLinked;
}

-(void) checkDropBox{
    if(![DBAuthHelperOSX sharedHelper].isLoading)
    {
        self.dropBox.enabled=YES;
        self.dropBox.state=YES;
    }
}

-(IBAction)toggleDropBox:(id)sender
{
    if (![[DBSession sharedSession] isLinked]) {
        self.dropBox.enabled=NO;
        self.dropBox.state=NO;
         [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(checkDropBox) name:DBAuthHelperOSXStateChangedNotification object:nil];
        [[DBAuthHelperOSX sharedHelper] authenticate];
    }
    else {
        [[DBSession sharedSession] unlinkAll];
    }
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver: self];
}


#pragma mark - preferences delegate

- (NSString *)identifier
{
    return self.title;
}

- (NSImage *)toolbarItemImage
{
    return [NSImage imageNamed:@"732-cloud-upload"];
}

- (NSString *)toolbarItemLabel
{
    return @"Cloud Storage";
}

@end
