#import <Foundation/Foundation.h>
#import "NSDistributedNotificationCenter.h"

@interface BPState: NSObject
@property (nonatomic, strong, nullable) NSString *code;
@property (nonatomic, strong, nullable) NSString *secret;
@property (nonatomic) BOOL connected;
// `error` overrules `connected`. If it says `connected` and `error` is not nil,
// that's a bug but we are considered not connected
@property (nonatomic, strong, nullable) NSError *error;
- (instancetype __nonnull)initWithCode:(NSString * __nullable)code
                                secret:(NSString * __nullable)secret
				             connected:(BOOL)connected
				                 error:(NSError * __nullable)error;

- (void)broadcast;
- (void)writeToDiskWithError:(NSError * __nullable * __nullable)writeErr;

// if this returns nil but the error isn't set, that means the file just doesn't exist
// if the error is set, then there was an actual error with reading it
+ (instancetype __nullable)readFromDiskWithError:(NSError * __nullable * __nullable)readErr;
@end
