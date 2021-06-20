//
//  MLBackgroundSettings.m
//  Monal
//
//  Created by Anurodh Pokharel on 11/19/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import "HelperTools.h"
#import "MLBackgroundSettings.h"
#import "MLSwitchCell.h"
#import "MLImageManager.h"
@import CoreServices;
@import AVFoundation;

@interface MLBackgroundSettings ()
@property (nonatomic, strong) NSMutableArray* photos;
@property (nonatomic, strong) NSArray* imageList;
@property (nonatomic, assign) NSUInteger selectedIndex;
@property (nonatomic, assign) NSUInteger displayedPhotoIndex;
@property (nonatomic, strong) UIImage* leftImage;
@property (nonatomic, strong) UIImage* rightImage;

@end

@implementation MLBackgroundSettings

- (void)viewDidLoad {
    [super viewDidLoad];

    [self.tableView registerNib:[UINib nibWithNibName:@"MLSwitchCell" bundle:[NSBundle mainBundle]] forCellReuseIdentifier:@"AccountCell"];

    self.title = NSLocalizedString(@"Backgrounds", @"");

    self.imageList = @[@"Golden_leaves_by_Mauro_Campanelli",
                       @"Stop_the_light_by_Mato_Rachela",
                       @"THE_'OUT'_STANDING_by_ydristi",
                       @"Tie_My_Boat_by_Ray_Garcia",
                       @"Winter_Fog_by_Daniel_Vesterskov",
                       ];
}

-(void) viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];

    [self sendBackgroundChangeNotification];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 3;
}

-(NSString *) tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return NSLocalizedString(@"Select a background to display behind conversations", @"");
}

-(NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    return NSLocalizedString(@"Default chat backgrounds are from the Ubuntu project.", @"") ;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if(indexPath.row == 0)
    {
        MLSwitchCell* cell = (MLSwitchCell *)[tableView dequeueReusableCellWithIdentifier:@"AccountCell"];
        [cell initCell:NSLocalizedString(@"Chat Backgrounds", @"") withToggleDefaultsKey:@"ChatBackgrounds"];
        return cell;
    }
    else if(indexPath.row == 1)
    {
        UITableViewCell* cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"SelectCell"];
        cell.textLabel.text = NSLocalizedString(@"Select Background", @"");
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    else
    {
        UITableViewCell* cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"SelectCell"];
#if TARGET_OS_MACCATALYST
        cell.textLabel.text = NSLocalizedString(@"Select File", @"");
#else
        cell.textLabel.text = NSLocalizedString(@"Select From Photos", @"");
#endif
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
}


-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    switch(indexPath.row)
    {
        case 1: {
            [self showImages];
            break;
        }
        case 2: {
            [self showPhotos];
            break;
        }
    }
}

-(void) showPhotos
{
#if TARGET_OS_MACCATALYST
    //UTI @"public.data" for everything
    NSString *images = (NSString *)kUTTypeImage;
    UIDocumentPickerViewController *imagePicker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[images] inMode:UIDocumentPickerModeImport];
    imagePicker.allowsMultipleSelection=NO;
    imagePicker.delegate=self;
    [self presentViewController:imagePicker animated:YES completion:nil];
#else
    UIImagePickerController *imagePicker = [[UIImagePickerController alloc] init];
    imagePicker.delegate = self;
    imagePicker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted){
        if(granted)
            dispatch_async(dispatch_get_main_queue(), ^{
                [self presentViewController:imagePicker animated:YES completion:nil];
            });
    }];
#endif
}


-(void) showImages
{
    self.photos = [NSMutableArray array];

    NSString *currentBackground = [[HelperTools defaultsDB] objectForKey:@"BackgroundImage"];
    self.selectedIndex = -1;
    // Add photos
    [self.imageList enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL* _Nonnull stop) {
        NSString* name = (NSString*) obj;
        IDMPhoto* photo = [IDMPhoto photoWithImage:[UIImage imageNamed:name]];
        photo.caption = [name stringByReplacingOccurrencesOfString:@"_" withString:@" "];
        [self.photos addObject:photo];
        
        if([currentBackground isEqualToString:name])
        {
            self.selectedIndex = idx;
        }
    }];
 
    // Create browser (must be done each time photo browser is
    // displayed. Photo browser objects cannot be re-used)
    IDMPhotoBrowser* browser = [[IDMPhotoBrowser alloc] initWithPhotos:self.photos];
    browser.navigationItem.title = NSLocalizedString(@"Select a Background", @"");
    browser.delegate = self;
    UIBarButtonItem* close = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Close", @"") style:UIBarButtonItemStyleDone target:self action:@selector(close)];
    browser.navigationItem.leftBarButtonItem = close;
    
    browser.autoHideInterface = NO;
    browser.displayArrowButton = YES;
    browser.displayCounterLabel = YES;
    browser.displayActionButton = NO;
    browser.displayToolbar = YES;
    
    self.leftImage = [UIImage imageNamed:@"IDMPhotoBrowser_arrowLeft"];
    self.rightImage = [UIImage imageNamed:@"IDMPhotoBrowser_arrowRight"];
    browser.leftArrowImage = self.leftImage;
    browser.rightArrowImage = self.rightImage;

    UINavigationController* nav = [[UINavigationController alloc] initWithRootViewController:browser];

    // Present
    [self presentViewController:nav animated:YES completion:nil];
}

-(void) sendBackgroundChangeNotification
{
    //don't queue this notification because it should be handled immediately
    [[NSNotificationCenter defaultCenter] postNotificationName:kMonalBackgroundChanged object:nil userInfo:nil];
}

-(void) close {
    [[HelperTools defaultsDB] setObject:[self.imageList objectAtIndex:self.displayedPhotoIndex] forKey:@"BackgroundImage"];
    [self sendBackgroundChangeNotification];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] init];
    [coordinator coordinateReadingItemAtURL:urls.firstObject options:NSFileCoordinatorReadingForUploading error:nil byAccessor:^(NSURL * _Nonnull newURL) {
        NSData* data = [NSData dataWithContentsOfURL:newURL];
        if([[MLImageManager sharedInstance] saveBackgroundImageData:data])
        {
            [[HelperTools defaultsDB] setObject:@"CUSTOM" forKey:@"BackgroundImage"];
            [self sendBackgroundChangeNotification];
        }
    }];
}

#pragma mark - photo browser delegate
- (void)photoBrowser:(IDMPhotoBrowser *)photoBrowser didShowPhotoAtIndex:(NSUInteger)index
{
   self.displayedPhotoIndex=index;
}

- (void)photoBrowser:(IDMPhotoBrowser *)photoBrowser didDismissAtPageIndex:(NSUInteger)index
{
    [[HelperTools defaultsDB] setObject:[self.imageList objectAtIndex:index] forKey:@"BackgroundImage"];
}

#pragma mark - image picker delegate
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<NSString *,id> *)info
{
    [self dismissViewControllerAnimated:YES completion:nil];
    
    NSString* mediaType = info[UIImagePickerControllerMediaType];
    if([mediaType isEqualToString:(NSString *)kUTTypeImage]) {
        UIImage* selectedImage = info[UIImagePickerControllerEditedImage];
        if(!selectedImage)
            selectedImage = info[UIImagePickerControllerOriginalImage];
        NSData* jpgData=  UIImageJPEGRepresentation(selectedImage, 0.5f);
        if(jpgData)
        {
            if([[MLImageManager sharedInstance] saveBackgroundImageData:jpgData]) {
                [[HelperTools defaultsDB] setObject:@"CUSTOM" forKey:@"BackgroundImage"];
            }
        }
    }
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker
{
    [self dismissViewControllerAnimated:YES completion:nil];
}


@end
