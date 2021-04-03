//
//  MLChatImageCell.h
//  Monal
//
//  Created by Anurodh Pokharel on 12/24/17.
//  Copyright © 2017 Monal.im. All rights reserved.
//

#import "MLBaseCell.h"

@class MLMessage;

@interface MLChatImageCell : MLBaseCell

-(void) initCellWithMLMessage:(MLMessage*) message;

-(UIImage*) getDisplayedImage;

@end

