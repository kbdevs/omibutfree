#ifdef __OBJC__
#import <UIKit/UIKit.h>
#else
#ifndef FOUNDATION_EXPORT
#if defined(__cplusplus)
#define FOUNDATION_EXPORT extern "C"
#else
#define FOUNDATION_EXPORT extern
#endif
#endif
#endif

#import "OpusFlutterIosPlugin.h"

FOUNDATION_EXPORT double opus_flutter_iosVersionNumber;
FOUNDATION_EXPORT const unsigned char opus_flutter_iosVersionString[];

