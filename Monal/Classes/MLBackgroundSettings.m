//
//  MLBackgroundSettings.m
//  Monal
//
//  Created by Anurodh Pokharel on 11/19/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import "MLBackgroundSettings.h"
#import "MLSettingCell.h"
#import "MLImageManager.h"
@import CoreServices;
@import AVFoundation;

@interface MLBackgroundSettings ()
@property (nonatomic, strong) NSMutableArray *photos;
@property (nonatomic, strong) NSArray *imageList;
@property (nonatomic, assign) NSUInteger selectedIndex;
@end

@implementation MLBackgroundSettings

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=@"Backgrounds";
    
    self.imageList = @[@"Golden_leaves_by_Mauro_Campanelli",
                       @"Stop_the_light_by_Mato_Rachela",
                       @"THE_'OUT'_STANDING_by_ydristi",
                       @"Tie_My_Boat_by_Ray_García",
                       @"Winter_Fog_by_Daniel_Vesterskov",
                       ];
    
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
    return @"Select a background to display behind conversations";
}

-(NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    return @"Default chat backgrounds are from the Ubuntu project." ;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    
    UITableViewCell* toreturn;
    switch (indexPath.row) {
        case 0: {
            MLSettingCell* cell=[[MLSettingCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"AccountCell"];
            cell.parent= self;
            cell.switchEnabled=YES;
            cell.defaultKey=@"ChatBackgrounds";
            cell.textLabel.text=@"Chat Backgrounds";
            toreturn=cell;
            break;
        }
            
        case 1: {
           UITableViewCell* cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"SelectCell"];
            cell.textLabel.text=@"Select Background";
            cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
            toreturn=cell;
            break;
        }
            
        case 2: {
            UITableViewCell* cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"SelectCell"];
            cell.textLabel.text=@"Select From Photos";
            cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
            toreturn=cell;
            break;
        }
            
        default:
            break;
    }
   
    return toreturn;
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
        default: break;
            
    }
    
}

-(void) showPhotos
{
    UIImagePickerController *imagePicker = [[UIImagePickerController alloc] init];
    imagePicker.delegate =self;
     imagePicker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
        if(granted)
        {
            [self presentViewController:imagePicker animated:YES completion:nil];
        }
    }];
}

-(void) showImages
{
    self.photos = [NSMutableArray array];

    NSString *currentBackground = [[NSUserDefaults standardUserDefaults] objectForKey:@"BackgroundImage"];
    self.selectedIndex=-1;
    // Add photos
    [self.imageList enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSString *name =(NSString *) obj;
        IDMPhoto *photo= [IDMPhoto photoWithImage:[UIImage imageNamed:name]];
        photo.caption = [name stringByReplacingOccurrencesOfString:@"_" withString:@" "];
        [self.photos addObject:photo];
        
        if([currentBackground isEqualToString:name])
        {
            self.selectedIndex=idx;
        }
    }];
 
    // Create browser (must be done each time photo browser is
    // displayed. Photo browser objects cannot be re-used)
    IDMPhotoBrowser *browser = [[IDMPhotoBrowser alloc] initWithPhotos:self.photos];
    browser.navigationItem.title=@"Select a Background";
    browser.delegate=self;
    
    UINavigationController *nav =[[UINavigationController alloc] initWithRootViewController:browser];

    // Present
    [self.navigationController presentViewController:nav animated:YES completion:nil];
}


#pragma mark - photo browser delegate

- (NSUInteger)numberOfPhotosInPhotoBrowser:(IDMPhotoBrowser *)photoBrowser {
    return self.photos.count;
}

- (id <IDMPhoto>)photoBrowser:(IDMPhotoBrowser *)photoBrowser photoAtIndex:(NSUInteger)index {
    if (index < self.photos.count) {
        return [self.photos objectAtIndex:index];
    }
    return nil;
}

- (id <IDMPhoto>)photoBrowser:(IDMPhotoBrowser *)photoBrowser thumbPhotoAtIndex:(NSUInteger)index;
{
    if (index < self.photos.count) {
        return [self.photos objectAtIndex:index];
    }
    return nil;
}

- (void)photoBrowser:(IDMPhotoBrowser *)photoBrowser didDismissAtPageIndex:(NSUInteger)index
{
    [[NSUserDefaults standardUserDefaults] setObject:[self.imageList objectAtIndex:index] forKey:@"BackgroundImage"];
}

#pragma mark - image picker delegate
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<NSString *,id> *)info
{
    [self dismissViewControllerAnimated:YES completion:nil];
    
    NSString *mediaType = info[UIImagePickerControllerMediaType];
    if([mediaType isEqualToString:(NSString *)kUTTypeImage]) {
        UIImage *selectedImage= info[UIImagePickerControllerEditedImage];
        if(!selectedImage) selectedImage= info[UIImagePickerControllerOriginalImage];
        NSData *jpgData=  UIImageJPEGRepresentation(selectedImage, 0.5f);
        if(jpgData)
        {
            
            if([[MLImageManager sharedInstance] saveBackgroundImageData:jpgData]) {
                [[NSUserDefaults standardUserDefaults] setObject:@"CUSTOM" forKey:@"BackgroundImage"];
            }
            
        }
        
    }
    
}



- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker
{
    [self dismissViewControllerAnimated:YES completion:nil];
}


@end
