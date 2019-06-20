//
//  MLImageView.m
//  Monal
//
//  Created by Anurodh Pokharel on 10/1/16.
//  Copyright © 2016 Monal.im. All rights reserved.
//

#import "MLImageView.h"

@implementation MLImageView

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    
    // Drawing code here.
}

- (void)mouseDown:(NSEvent *)theEvent
{
    if (theEvent.type != NSLeftMouseDown) {
        [super mouseDown:theEvent];
    }
}

-(void) openlink
{
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:self.webURL]];
}


- (void)mouseUp:(NSEvent *)theEvent {
    if(self.webURL) {
        [self openlink];
    } else
    if([self.previewTarget respondsToSelector:@selector(showImagePreview:)]) {
        [NSApp sendAction:@selector(showImagePreview:) to:self.previewTarget from:self];
    }
}

- (void) updateLayerWithImage:(NSImage *) image {
    CGFloat desiredScaleFactor = [self.window backingScaleFactor];
    CGFloat actualScaleFactor = [image recommendedLayerContentsScale:desiredScaleFactor];
    
    id layerContents = [image layerContentsForContentsScale:actualScaleFactor];
    
    self.layer.contentsGravity=kCAGravityResizeAspectFill;
    [self.layer setContents:layerContents];
    [self.layer setContentsScale:actualScaleFactor];
}


@end
