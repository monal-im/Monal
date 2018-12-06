//
//  MLLinkCell.h
//  Monal-OSX
//
//  Created by Anurodh Pokharel on 12/6/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import "MLChatViewCell.h"

NS_ASSUME_NONNULL_BEGIN

@interface MLLinkViewCell : MLChatViewCell

//use messagetext
//use previewImage
@property (nonatomic, strong) NSString *imageUrl;
@property (nonatomic, weak) IBOutlet NSView *bubbleView;

-(void) loadPreviewWithCompletion:(void (^)(void))completion;

-(void) openlink: (id) sender;
@end

NS_ASSUME_NONNULL_END
