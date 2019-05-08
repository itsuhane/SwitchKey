//
//  InputSource.m
//  InputSource
//
//  Created by Jinyu Li on 2019/03/16.
//  Copyright © 2019 Jinyu Li. All rights reserved.
//

#import "InputSource.h"
@import Cocoa;
@import Carbon;

@implementation InputSource {
    TISInputSourceRef inputSource;
}

+(InputSource*)current {
    TISInputSourceRef inputSource = TISCopyCurrentKeyboardInputSource();
    InputSource* source = [[InputSource alloc] init:inputSource];
    CFRelease(inputSource);
    return source;
}

+(nullable InputSource*)with:(NSString*)inputSourceID {
    InputSource *result = nil;

    CFMutableDictionaryRef properties = CFDictionaryCreateMutable(NULL, 0, NULL, NULL);
    CFDictionarySetValue(properties, kTISPropertyInputSourceIsEnabled, kCFBooleanTrue);
    CFDictionarySetValue(properties, kTISPropertyInputSourceIsSelectCapable, kCFBooleanTrue);
    CFArrayRef inputSourceList = TISCreateInputSourceList(properties, false);
    if (inputSourceList == NULL) {
        CFRelease(properties);
        return nil;
    }

    CFIndex count = CFArrayGetCount(inputSourceList);
    for (CFIndex i = 0; i < count; ++i) {
        InputSource *source = [[InputSource alloc] init:(TISInputSourceRef)CFArrayGetValueAtIndex(inputSourceList, i)];
        if ([inputSourceID isEqualToString:[source inputSourceID]]) {
            result = source;
        }
    }

    CFRelease(inputSourceList);
    CFRelease(properties);
    return result;
}

-(id)init:(TISInputSourceRef)inputSource {
    if(self = [super init]) {
        self->inputSource = inputSource;
        CFRetain(inputSource);
    }
    return self;
}

-(NSString*)inputSourceID {
    return (__bridge NSString * _Nonnull)((CFStringRef)TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID));
}

-(NSString*)localizedName {
    return (__bridge NSString * _Nonnull)((CFStringRef)TISGetInputSourceProperty(inputSource, kTISPropertyLocalizedName));
}

-(NSImage*)icon {
    IconRef iconRef = NULL;
    NSURL *url = NULL;
    if((iconRef = (IconRef)TISGetInputSourceProperty(inputSource, kTISPropertyIconRef)) == NULL) {
        url = (__bridge NSURL*)TISGetInputSourceProperty(inputSource, kTISPropertyIconImageURL);
    }
    return iconRef ? [[NSImage alloc] initWithIconRef:iconRef] : [[NSImage alloc] initWithContentsOfURL:url];
}

-(void)activate {
    TISSelectInputSource(inputSource);
}

-(void)dealloc {
    CFRelease(inputSource);
}

@end
