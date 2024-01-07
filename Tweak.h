@interface IDSValidationSession : NSObject
- (NSDictionary * __nonnull)headersBySigningData:(NSData * __nonnull)data serverTimestamp:(int)ts error:(NSError * __nullable * __nullable)error;
@end

@interface IDSRegistrationCenter
+ (instancetype __nonnull)sharedInstance;
- (id<NSObject> __nullable)_sendAuthenticateRegistration:(id __nullable)reg;
@end

@interface IDSRegistration : NSObject
@end

@interface IDSServiceProperties : NSObject
	@property (nonatomic,retain) NSString * __nullable identifier;
@end

@interface IDSDAccount
@property(readonly, nonatomic) IDSServiceProperties * __nullable service;
- (id __nullable)_rebuildRegistrationInfo:(BOOL)rebuild;
- (void)_checkRegistration;
- (void)activateRegistration;
- (void)reregister;
- (void)setRegistrationStatus:(int)status error:(NSError * __nullable)error alertInfo:(id __nullable)alertInfo;
- (IDSRegistration * __nullable)registration;
@end

@interface IDSDAccountController : NSObject
+ (instancetype __nonnull)sharedInstance;
- (NSArray<IDSDAccount *> * __nonnull)accounts;
@end

@interface CKSettingsMessagesController
- (void)onboardingControllerDidFinish:(id __nonnull)onboardingController;
@end
