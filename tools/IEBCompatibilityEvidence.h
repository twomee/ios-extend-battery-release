#import <Foundation/Foundation.h>

// A metadata match is diagnostic evidence, never runtime admission.
NSDictionary *IEBCompatibilitySummary(id observations, NSUInteger expectedCount, BOOL imagesLoaded);

NSDictionary *IEBInspectCompatibilityMember(NSArray<NSString *> *spec);
