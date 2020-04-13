//
//  MLChatMapsCell.h
//  Monal
//
//  Created by Friedrich Altheide on 29.03.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//
#import <MapKit/MapKit.h>

#import "MLBaseCell.h"


@interface MLChatMapsCell : MLBaseCell

@property (nonatomic, weak) IBOutlet MKMapView *map;

@property (nonatomic) CLLocationDegrees longitude;
@property (nonatomic) CLLocationDegrees latitude;

-(void) loadCoordinatesWithCompletion:(void (^)(void))completion;

@end

