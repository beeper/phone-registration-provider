#import <UIKit/UIKit.h>
#import <sys/utsname.h>
#import <sys/sysctl.h>
#import <rootless.h>
#import "SRWebSocket.h"
#import "Tweak.h"
#import "MobileGestalt.h"
#import "State.h"
#import "NSDistributedNotificationCenter.h"
#import "Constants.h"

#define LOG(...) log_impl([NSString stringWithFormat:__VA_ARGS__])

// cheap globals 'cause IPC is stupid and we'll figure it out later
static NSError *currentError;

// In identityservicesd, this stores the current state to be sent when requested by the Settings app.
// The Settings app requests the state when it is opened and stores it here
// to be used in the hook for the messages section footer text
static BPState *currentState;

// Store the validation data expiry timestamp (10 minutes from now)
static int validationDataExpiry = 0;
static NSData *validationData;

// for retrieving validation data
static dispatch_semaphore_t validationDataCompletion;

// The identifiers for this device/os/etc
static NSDictionary *identifiers;

void log_impl(NSString *logStr) {
	NSLog(@"BPS: %@", [logStr stringByReplacingOccurrencesOfString:@"\n" withString:@" "]);
	NSString *logFile = ROOT_PATH_NS(@"/var/mobile/beepserv.log");
	NSFileManager *fm = NSFileManager.defaultManager;
	if (![fm fileExistsAtPath:logFile])
		[fm createFileAtPath:logFile contents:nil attributes:nil];
	NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:logFile];
	[fileHandle seekToEndOfFile];
	[fileHandle writeData:[[NSString stringWithFormat:@"%@\n", logStr] dataUsingEncoding:NSUTF8StringEncoding]];
	[fileHandle closeFile];
}

@interface SocketDelegate : NSObject <SRWebSocketDelegate>
@property (nonatomic, strong, nullable) SRWebSocket *socket;
@property (nonatomic, strong, nonnull) dispatch_queue_t validationQueue;
@property (nonatomic, strong, nullable) NSURL *wsURL;
// we're separating `code` and `registered` 'cause if we get deregistered, we still want to keep
// the code that we previously registered with around so that we can re-submit it to try and re-register
// with the same code and the user doesn't have to switch anything up
@property (nonatomic, strong, nullable) NSString *code;
@property (nonatomic, strong, nullable) NSString *secret;
// This method can throw
- (void)tryStartConnection;
- (void)retryWSInLoopWithError:(NSError * __nonnull)error;
@end

@implementation SocketDelegate

- (instancetype)initWithURL:(NSString * __nullable)wsURL {
	self = [super init];
	self.validationQueue = dispatch_queue_create("socketDelegateValidationQueue", DISPATCH_QUEUE_SERIAL);
	NSString *trimmed = [wsURL stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	LOG(@"Got trimmed url string: '%@'", trimmed);
	self.wsURL = [NSURL URLWithString:trimmed];

	NSError *readErr;
	BPState *state = [BPState readFromDiskWithError:&readErr];
	LOG(@"Upon startup, read state as %@", state);

	if (readErr) {
		LOG(@"Couldn't read BPState from disk upon startup: %@", readErr);
	} else {
		self.code = state.code;
		self.secret = state.secret;
	}

	return self;
}

- (NSString *)description {
	return [NSString stringWithFormat:@"<%@: wsURL = %@, socket = %@, code = %@, secret = %@>", NSStringFromClass(self.class), self.wsURL, self.socket, self.code, self.secret];
}

- (void)tryStartConnection {
	if (!self.wsURL) {
		LOG(@"wsURL is nil, not trying to connect");
		return;
	}

	NSURLRequest *request = [NSURLRequest requestWithURL:self.wsURL];

	// create the socket and assign delegate
	self.socket = [SRWebSocket.alloc initWithURLRequest:request];
	self.socket.delegate = self;

	// open socket
	[self.socket open];
}

- (void)getValidationDataWithCompletion:(void(^__nonnull)(NSError * __nullable, NSData * __nullable))completion {
	// Check if we have validation data
	if (validationData != nil && validationDataExpiry > (int)[NSDate.date timeIntervalSince1970]) {
		LOG(@"Validation data already exists, using that");
		completion(nil, validationData);
		return;
	}
	
	// Just start running the whole registration process so that we can get the validation data
	IDSDAccountController *controller = [%c(IDSDAccountController) sharedInstance];
	NSArray<IDSDAccount *> *accounts = controller.accounts;
	
	for (IDSDAccount *acc in accounts) {
		LOG(@"Account: %@, Registration: %@", acc, acc.registration);
		
		// Only continue if it's an iMessage account
		if (!acc.service || ![acc.service.identifier isEqual: @"com.apple.madrid"]) {
			continue;
		}
		
		if (!acc.registration) {
			LOG(@"Account without registration found, trying to activate it");
			// Calling this in the validation queue async thread crashes the process,
			// so this needs to happen outside of that
			[acc activateRegistration];
		}
		
		LOG(@"Trying to reregister account");
		// This will lead to -[IDSRegistrationMessage setValidationData:] being called
		[acc reregister];
	}
	
	dispatch_async(self.validationQueue, ^{
		validationDataCompletion = dispatch_semaphore_create(0);
		currentError = nil;

		NSError *error;

		if (dispatch_semaphore_wait(validationDataCompletion, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC)) != 0) {
			LOG(@"validationDataCompletion wait timed out");
			error = [NSError errorWithDomain:kSuiteName code:1 userInfo:@{@"Error Reason": @"semaphore_wait timed out"}];
		}

		error = error ?: currentError.copy;
		NSData *data = validationData.copy;

		currentError = nil;
		validationDataCompletion = nil;

		LOG(@"Running validation data completion with error %@, data %@", error, data);
		completion(error, data);
	});
}

- (void)sendPongTo:(SRWebSocket * __nonnull)webSocket {
	[self sendDict:@{ @"command": @"pong"}];
}

- (void)sendIdentifiersTo:(SRWebSocket * __nonnull)webSocket withID:(NSNumber *)ID {
	[self sendDict:@{
		@"command": @"response",
		@"data": @{
			@"versions": identifiers
		},
		@"id": ID
	}];
}

- (void)sendValidationDataToID:(NSNumber *)ID {
	[self getValidationDataWithCompletion:^(NSError * __nullable error, NSData * __nullable validationData){
		NSMutableDictionary *dataBody = NSMutableDictionary.new;

		if (error)
			dataBody[@"error"] = [NSString stringWithFormat:@"Couldn't retrieve validation data: %@", error];
		else
			dataBody[@"data"] = [validationData base64EncodedStringWithOptions:0];

		[self sendDict:@{
			@"command": @"response",
			@"data": dataBody,
			@"id": ID
		}];
	}];
}

- (void)webSocketDidOpen:(SRWebSocket *)webSocket {
	NSMutableDictionary *data = NSMutableDictionary.new;
	if (self.code && self.secret) {
		data[@"code"] = self.code;
		data[@"secret"] = self.secret;
	}

	NSMutableDictionary *req = @{
		@"command": @"register",
		@"data": data
	}.mutableCopy;

	LOG(@"Socket opened, sending %@", req);

	[self sendDict:req];
}

- (void)sendDict:(NSDictionary * __nonnull)dict {
	NSError *jsonErr;
	NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict options:0 error:&jsonErr];

	if (jsonErr)
		LOG(@"Couldn't send dict %@, as it couldn't be serialized: %@", dict, jsonErr);

	// so. for some incomprehensible reason, the precompiler for theos chokes when you include `{.*}`
	// in a string literal, so we have to cheat and escape them by inserting their unicode codes as
	// characters in format arguments
	NSString *sendStr = (jsonErr != nil) ?
		[NSString stringWithFormat:@"%C \"error\": \"Couldn't serialize to JSON: %@\" %C", 0x007b, jsonErr, 0x007b] :
		[NSString.alloc initWithData:jsonData encoding:NSUTF8StringEncoding];

	LOG(@"Sending string '%@'", sendStr);

	NSError *sendErr;
	[self.socket sendString:sendStr error:&sendErr];

	if (sendErr)
		LOG(@"Couldn't send identifiers: %@", sendErr);
}

- (void)saveStateWithCode:(NSString * __nullable)code
                      secret:(NSString * __nullable)secret
				   connected:(BOOL)connected
				       error:(NSError * __nullable)error {
	currentState = [BPState.alloc initWithCode:code secret:secret connected:connected error:error];
	
	[currentState broadcast];
	
	NSError *writeErr;
	[currentState writeToDiskWithError: &writeErr];

	if (writeErr)
		LOG(@"Couldn't write state to file: %@", writeErr);
}

- (void)saveRegistrationWithCode:(NSString * __nullable)code secret:(NSString * __nullable)secret {
	self.code = code;
	self.secret = secret;

	LOG(@"Was given registration code %@", code);

	[self saveStateWithCode:code secret:secret connected:self.socket.readyState == SR_OPEN error:nil];
}

- (void)retryWSInLoopWithError:(NSError * __nonnull)error {
	[self saveStateWithCode:self.code secret:self.secret connected:NO error:error];

	while (true) {
		// backoff
		sleep(2);

		@try {
			[self tryStartConnection];
			break;
		} @catch (NSException *exc) {
			LOG(@"Socket failed to connect again, waiting 2 seconds and trying again: %@", exc);
		}
	}
}

- (void)webSocket:(SRWebSocket *)webSocket didFailWithError:(NSError *)error {
	LOG(@"Socket failed with error: %@", error);
	self.socket = nil;
	[self retryWSInLoopWithError:error];
}

- (void)webSocket:(SRWebSocket *)webSocket didReceiveMessageWithString:(NSString *)message {
	LOG(@"Got message string '%@'", message);

	NSData *jsonData = [message dataUsingEncoding:NSUTF8StringEncoding];

	NSError *jsonErr;
	NSDictionary *object = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&jsonErr];

	if (jsonErr) {
		LOG(@"Couldn't parse text message as JSON: %@", jsonErr);
		return;
	}

	LOG(@"Got json object %@", object);

	id cmd = object[@"command"];

	if ([cmd isEqual:@"ping"]) {
		[self sendPongTo:webSocket];
	} else if ([cmd isEqual:@"get-version-info"]) {
		[self sendIdentifiersTo:webSocket withID:object[@"id"]];
	} else if ([cmd isEqual:@"get-validation-data"]) {
		[self sendValidationDataToID:object[@"id"]];
	} else if ([cmd isEqual:@"response"]) {
		NSDictionary *data = object[@"data"];
		if (data && data[@"code"] && data[@"secret"]) {
			[self saveRegistrationWithCode:data[@"code"] secret:data[@"secret"]];
		} else {
			LOG(@"data object in response had no object `code`: %@", data);
		}
	}
}

- (void)webSocket:(SRWebSocket *)webSocket didReceiveMessageWithData:(NSData *)data {
	LOG(@"We received a data message, not handling");
}

- (void)webSocket:(SRWebSocket *)webSocket didCloseWithCode:(NSInteger)code reason:(NSString *)reason wasClean:(BOOL)wasClean {
	LOG(@"The server closed the ws connection with code %ld and reason %@, was clean: %d; will try to reconnect", (long)code, reason, wasClean);

	NSDictionary *userInfo = @{
		@"Error Reason": [NSString stringWithFormat:@"webSocket closed with reason: %@", reason]
	};
	[self retryWSInLoopWithError:[NSError errorWithDomain:kSuiteName code:code userInfo:userInfo]];
}

@end

%hook IDSRegistrationMessage

- (void)setValidationData:(id)data {
	LOG(@"Got validation data: %@", data);
	validationDataExpiry = (int)[NSDate.date timeIntervalSince1970] + 10 * 60;
	validationData = data;

	if (validationDataCompletion)
		dispatch_semaphore_signal(validationDataCompletion);

	%orig(data);
}

%end

%hook CKSettingsMessagesController

- (id)_switchFooterText:(BOOL *)arg1 {
	NSString *orig = %orig;

	if (currentState.connected) {
		return currentState.code ?
			[NSString stringWithFormat:@"Your device is currently being used for beepserv. Your code is %@\n\n%@", currentState.code, orig] :
			[NSString stringWithFormat:@"Your device is connecting to the beeper relay. Please wait a second...\n\n%@", orig];
	} else if (currentState) {
		NSString *errString = currentState.error.description ?: @"Unknown Error";
		return [NSString stringWithFormat:@"Your device is not connected to the beeper relay due to the following: %@. Please check the beepserv instructions and open an issue if you are unable to get this working.\n\n%@", errString, orig];
	} else {
		return [NSString stringWithFormat:@"Your device is not connected to the beeper relay. Please check the beepserv instructions and open an issue if you are unable to get this working.\n\n%@", orig];
	}
}

- (void)setMadridEnabled:(id)enabled specifier:(id)specifier {
	LOG(@"Called _setMadridEnabled:%@ specifier:%@, doing nothing", enabled, specifier);
}

- (BOOL)_isMadridSwitchOn {
	return NO;
}

- (id)presentingViewControllerForOnboardingController:(id)controller {
	LOG(@"Called presentingViewControllerForOnboardingController:%@, doing nothing", controller);
	return nil;
}

- (id)onboardingController {
	LOG(@"Called onboardingController; returning orig");
	return %orig();
}

- (void)setOnboardingController:(id)onboardingController {
	LOG(@"Called setOnboardingController:%@; calling didFinish after setting", onboardingController);
	%orig(onboardingController);
	dispatch_async(dispatch_get_main_queue(), ^{
		[self onboardingControllerDidFinish:onboardingController];
	});
}

%end

NSDictionary *getIdentifiers() {
	struct utsname systemInfo;
	uname(&systemInfo);

	NSString *model = [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];

	size_t malloc_size = 10;
	char *buildNumberBuf = malloc(malloc_size);
	sysctlbyname("kern.osversion\0", (void *)buildNumberBuf, &malloc_size, NULL, 0);

	// we don't need to free `buildNumberBuf` if we pass it into this method
	NSString *buildNumber = [NSString stringWithCString:buildNumberBuf encoding:NSUTF8StringEncoding];

	UIDevice *device = UIDevice.currentDevice;
	NSString *iOSVersion = device.systemVersion;
	NSUUID *identifier = device.identifierForVendor;

	return @{
		@"hardware_version": model,
		@"software_name": @"iPhone OS",
		@"software_version": iOSVersion,
		@"software_build_id": buildNumber,
		@"unique_device_id": identifier.UUIDString, // not actually the devices's UDID, but a UUID
		@"serial_number": (__bridge NSString *)MGCopyAnswer(CFSTR("SerialNumber"))
	};
}

%ctor {
	NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];

	// This %ctor will be called every time identityservicesd or the settings app is restarted.
	// So we only want it to try to reinitialize stuff if it's in identityservicesd
	if (![bundleID isEqualToString:@"com.apple.identityservicesd"]) {
		[[NSDistributedNotificationCenter defaultCenter] addObserverForName: kNotificationUpdateState
			object: nil
			queue: [NSOperationQueue mainQueue]
			usingBlock: ^(NSNotification *notification)
		{
			NSDictionary *state = notification.userInfo;
			LOG(@"Received broadcasted state: %@", state);
			currentState = [BPState.alloc initWithCode:state[kCode] secret:state[kSecret] connected:((NSNumber *)state[kConnected]).boolValue error:state[kError]];
			NSError *diskWriteError;
			[currentState writeToDiskWithError:&diskWriteError];
			if (diskWriteError != nil) {
				LOG(@"Writing state to disk failed with error: %@", diskWriteError);
			}
		}];
		[[NSDistributedNotificationCenter defaultCenter]
			postNotificationName: kNotificationRequestStateUpdate
			object: nil
			userInfo: nil
		];
		return;
	}
	
	[[NSDistributedNotificationCenter defaultCenter] addObserverForName: kNotificationRequestStateUpdate
		object: nil
		queue: [NSOperationQueue mainQueue]
		usingBlock: ^(NSNotification *notification)
	{
		if (currentState) {
			[currentState broadcast];
		}
	}];

	NSString *filePath = ROOT_PATH_NS(@"/.beepserv_wsurl");
	NSString *wsURL = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:nil];

	wsURL = wsURL ?: @"https://registration-relay.beeper.com/api/v1/provider";

	static SocketDelegate *socketDelegate;
	socketDelegate = [SocketDelegate.alloc initWithURL:wsURL];
	LOG(@"Initialized delegate to %@", socketDelegate);

	// dispatch it after 5 seconds; I don't know the exact point in the program
	// where this won't fuck stuff up, so we're just cheating by waiting and it works
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
		@try {
			[socketDelegate tryStartConnection];
			LOG(@"started connection to %@", socketDelegate.wsURL);
		} @catch (NSException *exc) {
			LOG(@"Couldn't start socketDelegate, starting retry loop: %@", exc);

			NSError *err = [NSError errorWithDomain:exc.name code:0 userInfo:@{
    			NSUnderlyingErrorKey: exc,
    			NSDebugDescriptionErrorKey: exc.userInfo ?: @{ },
    			NSLocalizedFailureReasonErrorKey: (exc.reason ?: @"???")
			}];
			[socketDelegate retryWSInLoopWithError:err];
		}
	});

	identifiers = getIdentifiers();
	LOG(@"Got identifiers: %@", identifiers);
}
