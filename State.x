#import <Foundation/Foundation.h>
#import <rootless.h>
#import "State.h"
#import "NSDistributedNotificationCenter.h"
#import "Constants.h"

static NSString *stateFile = ROOT_PATH_NS(@"/var/mobile/Library/.beepserv_state");
static NSString *otherStateFile = ROOT_PATH_NS(@"/var/mobile/.beepserv_state");

@implementation BPState
- (instancetype __nonnull)initWithCode:(NSString * __nullable)code
					            secret:(NSString * __nullable)secret
				             connected:(BOOL)connected
				                 error:(NSError * __nullable)error {
	self = [super init];
	self.code = code;
	self.secret = secret;
	self.connected = connected;
	self.error = error;
	return self;
}

- (NSString * __nonnull)description {
	return [NSString stringWithFormat:@"<BPState code:%@ secret:%@ connected:%d error:%@", self.code, self.secret, self.connected, self.error];
}

- (NSDictionary * __nonnull)serializeToDictionary {
	NSMutableDictionary *state = @{
		kConnected: @(self.connected)
	}.mutableCopy;
	
	if (self.code)
		state[kCode] = self.code;
	
	if (self.secret)
		state[kSecret] = self.secret;
	
	if (self.error)
		state[kError] = self.error;
		
	return state;
}

- (void)broadcast {
	NSDictionary *state = [self serializeToDictionary];
		
	[[NSDistributedNotificationCenter defaultCenter]
		postNotificationName: kNotificationUpdateState
		object: nil
		userInfo: state
	];
}

- (void)writeToDiskWithError:(NSError * __nullable * __nullable)writeErr {
	NSDictionary *state = [self serializeToDictionary];

	NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"file://%@", stateFile]];
	[state writeToURL:url error:writeErr];
	NSURL *otherUrl = [NSURL URLWithString:[NSString stringWithFormat:@"file://%@", otherStateFile]];
	[state writeToURL:otherUrl error:writeErr];
}

+ (instancetype __nullable)readFromDiskWithError:(NSError * __nullable * __nullable)readErr {
	if (
		![NSFileManager.defaultManager fileExistsAtPath:stateFile isDirectory:nil] &&
		![NSFileManager.defaultManager fileExistsAtPath:otherStateFile isDirectory:nil]
	) {
		return nil;
	}

	NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"file://%@", stateFile]];
	NSDictionary *state = [NSDictionary dictionaryWithContentsOfURL:url error:readErr];

	if (readErr && *readErr) {
		NSError *otherReadErr;
		url = [NSURL URLWithString:[NSString stringWithFormat:@"file://%@", otherReadErr]];
		state = [NSDictionary dictionaryWithContentsOfURL:url error:&otherReadErr];
		if (otherReadErr) {
			*readErr = otherReadErr;
			return nil;
		}
	}

	BOOL connected = ((NSNumber *)state[kConnected]).boolValue;
	return [BPState.alloc initWithCode:state[kCode] secret:state[kSecret] connected:connected error:state[kError]];
}
@end
