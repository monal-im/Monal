//
//  DataLayerMigrations.h
//  monalxmpp
//
//  Created by Friedrich Altheide on 15.01.22.
//  Copyright © 2022 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <monalxmpp/MLSQLite.h>
#import <monalxmpp/DataLayer.h>

NS_ASSUME_NONNULL_BEGIN

@interface DataLayerMigrations : NSObject

+(BOOL) migrateDB:(MLSQLite*) db withDataLayer:(DataLayer*) dataLayer;

@end

NS_ASSUME_NONNULL_END
