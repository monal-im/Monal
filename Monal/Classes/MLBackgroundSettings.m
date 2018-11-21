//
//  MLBackgroundSettings.m
//  Monal
//
//  Created by Anurodh Pokharel on 11/19/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import "MLBackgroundSettings.h"
#import "MLSettingCell.h"

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
    return @"Select services to opt out of";
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
            toreturn=cell;
            break;
        }
            
        case 2: {
            UITableViewCell* cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"SelectCell"];
            cell.textLabel.text=@"Select Photo";
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
    [self showImages];
}


-(void) showImages
{
    self.photos = [NSMutableArray array];

    NSString *currentBackground = [[NSUserDefaults standardUserDefaults] objectForKey:@"BackgroundImage"];
    self.selectedIndex=-1; 
    // Add photos
    [self.imageList enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSString *name =(NSString *) obj;
        MWPhoto *photo= [MWPhoto photoWithImage:[UIImage imageNamed:name]];
        photo.caption = [name stringByReplacingOccurrencesOfString:@"_" withString:@" "];
        [self.photos addObject:photo];
        
        if([currentBackground isEqualToString:name])
        {
            self.selectedIndex=idx;
        }
    }];
 
    // Create browser (must be done each time photo browser is
    // displayed. Photo browser objects cannot be re-used)
    MWPhotoBrowser *browser = [[MWPhotoBrowser alloc] initWithDelegate:self];
    
    // Set options
    browser.displayActionButton = NO; // Show action button to allow sharing, copying, etc (defaults to YES)
    browser.displayNavArrows = NO; // Whether to display left and right nav arrows on toolbar (defaults to NO)
    browser.displaySelectionButtons = YES; // Whether selection buttons are shown on each image (defaults to NO)
    browser.zoomPhotosToFill = YES; // Images that almost fill the screen will be initially zoomed to fill (defaults to YES)
    browser.alwaysShowControls = YES; // Allows to control whether the bars and controls are always visible or whether they fade away to show the photo full (defaults to NO)
    browser.enableGrid = YES; // Whether to allow the viewing of all the photo thumbnails on a grid (defaults to YES)
    browser.startOnGrid = YES; // Whether to start on the grid of thumbnails instead of the first photo (defaults to NO)
    browser.autoPlayOnAppear = NO; // Auto-play first video
    
    UINavigationController *nav =[[UINavigationController alloc] initWithRootViewController:browser];

    // Present
    [self.navigationController presentViewController:nav animated:YES completion:nil];
}


- (NSUInteger)numberOfPhotosInPhotoBrowser:(MWPhotoBrowser *)photoBrowser {
    return self.photos.count;
}

- (id <MWPhoto>)photoBrowser:(MWPhotoBrowser *)photoBrowser photoAtIndex:(NSUInteger)index {
    if (index < self.photos.count) {
        return [self.photos objectAtIndex:index];
    }
    return nil;
}

- (id <MWPhoto>)photoBrowser:(MWPhotoBrowser *)photoBrowser thumbPhotoAtIndex:(NSUInteger)index;
{
    if (index < self.photos.count) {
        return [self.photos objectAtIndex:index];
    }
    return nil;
}

- (BOOL)photoBrowser:(MWPhotoBrowser *)photoBrowser isPhotoSelectedAtIndex:(NSUInteger)index {
    return index==self.selectedIndex?YES:NO;
}

- (void)photoBrowser:(MWPhotoBrowser *)photoBrowser photoAtIndex:(NSUInteger)index selectedChanged:(BOOL)selected {
    self.selectedIndex=index;
    [[NSUserDefaults standardUserDefaults] setObject:[self.imageList objectAtIndex:index] forKey:@"BackgroundImage"];
    [photoBrowser reloadData];
}



@end
