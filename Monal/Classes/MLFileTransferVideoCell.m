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

-(void) avplayerVCInit
{
    avplayerVC = [AVPlayerViewController new];
    avplayerVC.showsPlaybackControls = YES;
#if TARGET_OS_MACCATALYST
    avplayerVC.allowsPictureInPicturePlayback = NO;
#else
    avplayerVC.allowsPictureInPicturePlayback = YES;    
#endif
    avplayerVC.view.frame = CGRectMake(0, 0, self.videoView.frame.size.width, self.videoView.frame.size.height);
    avplayerVC.videoGravity = AVLayerVideoGravityResizeAspect;
}

-(void) avplayerConfigWithUrlStr:(NSString*)fileUrlStr andMimeType:(NSString*) mimeType fileName:(NSString*) fileName andVC:(UIViewController*) vc{
    for (UIView* subView in self.videoView.subviews)
    {
        [subView removeFromSuperview];
    }
    [self avplayerVCInit];

    NSURL* videoFileUrl = [[NSURL alloc] initFileURLWithPath:fileUrlStr isDirectory:NO];
    if(videoFileUrl == nil)
    {
        DDLogWarn(@"Returning early in av player cell!");
        return;
    }
    
    //some translations needed
    if([@"audio/mpeg" isEqualToString:mimeType])
    {
        DDLogDebug(@"Overwriting mimeType: '%@' with 'audio/mp4'...", mimeType);
        mimeType = @"audio/mp4";
    }
    
    AVURLAsset* videoAsset = [[AVURLAsset alloc] initWithURL:videoFileUrl options:@{
        @"AVURLAssetOutOfBandMIMETypeKey": mimeType
    }];
    avplayer = [AVPlayer playerWithPlayerItem:[AVPlayerItem playerItemWithAsset:videoAsset]];
    DDLogInfo(@"Created AVPlayer(%@): %@", mimeType, avplayer);
    avplayerVC.player = avplayer;
    
    [self.videoView addSubview:avplayerVC.view];
    [vc addChildViewController:avplayerVC];
    [avplayerVC didMoveToParentViewController:vc];
}

-(void)prepareForReuse{
    [super prepareForReuse];
}
@end
