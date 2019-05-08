//
//  InputSource.h
//  InputSource
//
//  Created by Jinyu Li on 2019/03/16.
//  Copyright © 2019 Jinyu Li. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface InputSource : NSObject

+(InputSource*)current;
+(nullable InputSource*)with:(NSString*)inputSourceID;
-(NSString*)inputSourceID;
-(NSString*)localizedName;
-(NSImage*)icon;
-(void)activate;
-(void)dealloc;

@end

NS_ASSUME_NONNULL_END
