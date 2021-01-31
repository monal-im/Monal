//
//  MLFileTransferFileViewController.m
//  Monal
//
//  Created by Jim Tsai(poormusic2001@gmail.com) on 2020/12/28.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import "MLFileTransferFileViewController.h"
#import "MBProgressHUD.h"
#import <WebKit/WebKit.h>

@interface MLFilePreviewItem : NSObject <QLPreviewItem>
@property(nullable, nonatomic) NSURL    *previewItemURL;
@property(nullable, nonatomic) NSString *previewItemTitle;
@end
@implementation MLFilePreviewItem
- (instancetype)initWithPreviewURL:(NSURL *)fileURL andTitle:(NSString *)title {
    self = [super init];
    if (self) {
        _previewItemURL = [fileURL copy];
        _previewItemTitle = [title copy];
    }
    return self;
}
@end


@interface MLFileTransferFileViewController ()
@property (nonatomic, strong) MBProgressHUD *loadingHUD;
@property (nonatomic, strong) NSURL *fileUrl;
@property (nonatomic, strong) NSString *fileLink;
@property (nonatomic, strong) NSURL *fileToUrl;
@property (nonatomic, strong) NSFileManager *fileManager;

@end


@implementation MLFileTransferFileViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.loadingHUD = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    self.loadingHUD.label.text = NSLocalizedString(@"Loading Data", @"");
    self.loadingHUD.mode = MBProgressHUDModeIndeterminate;
    self.loadingHUD.removeFromSuperViewOnHide = YES;
    
    self.fileManager = [NSFileManager defaultManager];
    
    self.dataSource = self;
    self.delegate = self;
    self.fileUrl = [NSURL fileURLWithPath:self.fileUrlStr];
}

- (NSInteger)numberOfPreviewItemsInPreviewController:(nonnull QLPreviewController *)controller {
    return 1;
}

- (nonnull id<QLPreviewItem>)previewController:(nonnull QLPreviewController *)controller previewItemAtIndex:(NSInteger)index {
    [self.loadingHUD setHidden:YES];
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *filePosition = [documentsDirectory stringByAppendingString:[NSString stringWithFormat:@"/%@",self.fileName]];
        
    NSError *fileError = nil;
    self.fileToUrl = [NSURL fileURLWithPath:filePosition];
    
    [self.fileManager copyItemAtURL:self.fileUrl toURL:self.fileToUrl error:&fileError];
    return [[MLFilePreviewItem alloc] initWithPreviewURL:self.fileToUrl andTitle:filePosition.lastPathComponent];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:NO];
    
    NSError *fileError = nil;
    [self.fileManager removeItemAtURL:self.fileToUrl error:&fileError];
}

@end



