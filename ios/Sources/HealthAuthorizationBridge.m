#import "HealthAuthorizationBridge.h"

@implementation HealthAuthorizationBridge
+ (void)requestAuthorizationWithStore:(HKHealthStore *)store
                          readingTypes:(NSSet<HKObjectType *> *)readTypes
                            completion:(void (^)(BOOL success, NSError * _Nullable error))completion {
    @try {
        [store requestAuthorizationToShareTypes:[NSSet set]
                                      readTypes:readTypes
                                     completion:completion];
    } @catch (NSException *exception) {
        // HealthKit can throw NSException synchronously for invalid purpose strings
        // or a missing capability. Swift 'do/catch' does not catch NSException.
        NSString *reason = exception.reason ?: exception.name;
        NSError *error = [NSError errorWithDomain:@"hu.oranaplo.healthkit.configuration"
                                             code:1001
                                         userInfo:@{NSLocalizedDescriptionKey:
             [NSString stringWithFormat:@"HealthKit konfigurációs/aláírási hiba: %@. Ellenőrizd a HealthKit jogosultságot és az Info.plist leírásokat.", reason]}];
        completion(NO, error);
    }
}
@end
