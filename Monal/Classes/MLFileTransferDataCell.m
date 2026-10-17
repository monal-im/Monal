//
//  MLFileTransferDataCell.m
//  Monal
//
//  Created by Jim Tsai(poormusic2001@gmail.com) on 2020/12/7.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import "MLFileTransferDataCell.h"
#import <monalxmpp/MLImageManager.h>
#import <monalxmpp/MLConstants.h>
#import <monalxmpp/MLFileTransfer.h>
#import <monalxmpp/HelperTools.h>

@implementation MLFileTransferDataCell

-(void)awakeFromNib
{
    [super awakeFromNib];
    
    // Initialization code

    self.fileTransferBackgroundView.layer.cornerRadius = 5.0f;
    self.fileTransferBackgroundView.layer.masksToBounds = YES;
    
    self.fileTransferBoarderView.layer.cornerRadius = 5.0f;
    self.fileTransferBoarderView.layer.borderWidth = 1.3f;
    self.fileTransferBoarderView.layer.borderColor = [UIColor colorWithRed:76.0/255.0 green:155.0/255.0 blue:223.0/255.0 alpha:1.0].CGColor;
    
    [self.loadingView setHidden:YES];
    [self.downloadImageView setHidden:NO];
    [self.sizeLabel setText:@""];
}

-(void)layoutSubviews
{
    if([MLFiletransfer isFileForHistoryIdInTransfer:self.messageDBId])
    {
        [self.loadingView setHidden:NO];
        [self.loadingView startAnimating];
        [self.downloadImageView setHidden:YES];
    }
    else
    {
        [self.loadingView setHidden:YES];
        [self.loadingView stopAnimating];
        [self.downloadImageView setHidden:NO];
    }
}

-(void) initCellForMessageId:(NSNumber*) messageId andFilename:(NSString*) filename andMimeType:(NSString* _Nullable) mimeType andFileSize:(long long) fileSize
{
    self.messageDBId = messageId;
    // files without a mime type should be checked before download
    self.transferStatus = mimeType ? transferFileTypeNeedDowndload : transferCheck;

    NSString* hintStr;
    if(mimeType != nil)
    {
       hintStr = [NSString stringWithFormat:@"%@ %@ (%@).", NSLocalizedString(@"Download", @""), filename, mimeType];

        NSString* readableFileSize = [NSByteCountFormatter stringFromByteCount:fileSize countStyle:NSByteCountFormatterCountStyleFile];
        [self.sizeLabel setText:readableFileSize];

    }
    else
    {
       hintStr = [NSString stringWithFormat:@"%@%@", NSLocalizedString(@"Check type and size on ", @""), filename];
        [self.sizeLabel setText:@""];
    }
    [self.fileTransferHint setText:hintStr];
    
    [self.loadingView setHidden:YES];
    [self.downloadImageView setHidden:NO];
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(void)copy:(id)sender {
    UIPasteboard* pboard = [UIPasteboard generalPasteboard];
    pboard.string = self.messageBody.text;
}

-(void)prepareForReuse
{
    [super prepareForReuse];
    self.messageBody.text = @"";
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated
{
    [super setSelected:selected animated:animated];
    
    // Configure the view for the selected state
}

- (void)doUIActions:(NSNotification*)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        
        [self.downloadImageView setHidden:NO];
        [self.loadingView stopAnimating];
        [self.loadingView setHidden:YES];
        
        [[NSNotificationCenter defaultCenter] removeObserver:self name:kMonalMessageFiletransferUpdateNotice object:nil];
    });
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
            
    UITouch* touch = [touches anyObject];
    CGPoint touchPoint = [touch locationInView:touch.view];
        
    CGPoint insidePoint = [self.fileTransferBackgroundView convertPoint:touchPoint fromView:touch.view];
    if ([self.fileTransferBackgroundView pointInside:insidePoint withEvent:nil]) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(doUIActions:) name:kMonalMessageFiletransferUpdateNotice object:nil];
        
        [self.loadingView setHidden:NO];
        [self.loadingView startAnimating];
        [self.downloadImageView setHidden:YES];
                
        switch (self.transferStatus) {
            case transferCheck:
                [MLFiletransfer checkMimeTypeAndSizeForHistoryID: self.messageDBId];
                break;
            case transferFileTypeNeedDowndload:
                [MLFiletransfer downloadFileForHistoryID:self.messageDBId];
                break;
            default:
                unreachable();
                break;
        }
    }
}

@end
