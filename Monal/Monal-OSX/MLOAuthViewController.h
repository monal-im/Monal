//
//  MLOAuthViewController.h
//  Monal
//
//  Created by Anurodh Pokharel on 1/1/16.
//  Copyright © 2016 Monal.im. All rights reserved.
//

#import <Cocoa/Cocoa.h>
@import WebKit;

@interface MLOAuthViewController : NSViewController <WebFrameLoadDelegate>


@property (nonatomic, weak) IBOutlet WebView *webView;
@property (nonatomic, strong)  NSURL *oAuthURL;
@property (nonatomic, copy)  void (^completionHandler)(NSString *token);


@end
