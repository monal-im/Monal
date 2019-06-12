//
//  MLImageView.h
//  Monal
//
//  Created by Anurodh Pokharel on 10/1/16.
//  Copyright © 2016 Monal.im. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface MLImageView : NSImageView

@property (nonatomic, weak) IBOutlet id previewTarget;
- (void) updateLayerWithImage:(NSImage *) image ;
@end
