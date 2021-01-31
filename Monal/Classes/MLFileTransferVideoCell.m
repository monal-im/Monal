//
//  MLFileTransferVideoCell.m
//  Monal
//
//  Created by Jim Tsai(poormusic2001@gmail.com) on 2020/12/23.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import "MLFileTransferVideoCell.h"


@implementation MLFileTransferVideoCell

AVPlayerViewController *avplayerVC;
AVPlayer *avplayer;

- (void)awakeFromNib {
    [super awakeFromNib];
    
    // Initialization code
    self.videoView.layer.cornerRadius = 5.0f;
    self.videoView.layer.masksToBounds = YES;
    [self avplayerVCInit];
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

-(void)avplayerVCInit
{
    avplayerVC = [[AVPlayerViewController alloc] init];
    avplayerVC.showsPlaybackControls = YES;
    avplayerVC.player.volume = 0;
#if TARGET_OS_MACCATALYST
    avplayerVC.allowsPictureInPicturePlayback = NO;
#else
    avplayerVC.allowsPictureInPicturePlayback = YES;    
#endif
    avplayerVC.view.frame = CGRectMake(0, 0, self.videoView.frame.size.width, self.videoView.frame.size.height);
    avplayerVC.videoGravity = AVLayerVideoGravityResizeAspect;
}

-(NSURL*)fileURLFromStr:(NSString*) fileUrlStr andFileName:(NSString*) fileName
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray *fileNameComponent = [fileName componentsSeparatedByString:@"."];
    NSString * fileExtension = @"";
    if (fileNameComponent.count > 1){
        fileExtension = fileNameComponent.lastObject;
    }
    //Add SymbolicLink to play video file.
    NSString *fileLink = [fileUrlStr stringByAppendingPathExtension:fileExtension];
    if (![fileManager fileExistsAtPath:fileLink])
    {
        NSError *fileError = nil;
        [fileManager createSymbolicLinkAtPath:fileLink withDestinationPath:fileUrlStr error:&fileError];
    }
    
    return  [[NSURL alloc] initFileURLWithPath:fileLink];
}

-(void)avplayerConfigWithUrlStr:(NSString*)fileUrlStr fileName:(NSString*) fileName andVC:(UIViewController*) vc{
    
    for (UIView *subView in self.videoView.subviews)
    {
        [subView removeFromSuperview];
    }

    [self avplayerVCInit];
        
    NSURL *videoFileUrl = [self fileURLFromStr:fileUrlStr andFileName:fileName];
    avplayer = [AVPlayer playerWithURL:videoFileUrl];
    avplayerVC.player = avplayer;
    
    [self.videoView addSubview:avplayerVC.view];
    [vc addChildViewController:avplayerVC];
    [avplayerVC didMoveToParentViewController:vc];
}

-(void)prepareForReuse{
    [super prepareForReuse];
}
@end
