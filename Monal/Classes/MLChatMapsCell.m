//
//  MLChatMapsCell.m
//  Monal
//
//  Created by Friedrich Altheide on 29.03.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import "MLChatMapsCell.h"
#import "MLImageManager.h"
@import QuartzCore;

@implementation MLChatMapsCell

- (void)awakeFromNib {
    [super awakeFromNib];
    // Initialization code
    self.map.layer.cornerRadius=15.0f;
    self.map.layer.masksToBounds=YES;
}

-(void) loadCoordinatesWithCompletion:(void (^)(void))completion {
    // Remove old annotations
    [self.map removeAnnotations:self.map.annotations];

    CLLocationCoordinate2D geoLocation = CLLocationCoordinate2DMake(self.latitude, self.longitude);

    MKPointAnnotation *geoPin = [[MKPointAnnotation alloc]init];
    geoPin.coordinate = geoLocation;
    [self.map addAnnotation:geoPin];

    MKCoordinateRegion viewRegion = MKCoordinateRegionMakeWithDistance(geoLocation, 1500, 1500);

    [self.map setRegion:viewRegion animated:FALSE];
}

-(BOOL) canPerformAction:(SEL)action withSender:(id)sender
{
    return FALSE;
}

-(void)prepareForReuse{
    [super prepareForReuse];
}


@end
