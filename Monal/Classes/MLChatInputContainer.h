//
//  MLChatInputContainer.h
//  Monal
//
//  Created by Anurodh Pokharel on 1/20/20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "MLResizingTextView.h"

@protocol ChatInputActionDelegage

@optional
- (void) doScrollDownAction;

@end

NS_ASSUME_NONNULL_BEGIN

@interface MLChatInputContainer : UIView

@property (nonatomic, weak) IBOutlet MLResizingTextView* chatInput;
@property (nonatomic, weak) id <ChatInputActionDelegage> chatInputActionDelegate;
@end

NS_ASSUME_NONNULL_END
