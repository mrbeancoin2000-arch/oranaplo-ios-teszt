#import <Foundation/Foundation.h>
#import <HealthKit/HealthKit.h>

NS_ASSUME_NONNULL_BEGIN
@interface HealthAuthorizationBridge : NSObject
+ (void)requestAuthorizationWithStore:(HKHealthStore *)store
                          readingTypes:(NSSet<HKObjectType *> *)readTypes
                            completion:(void (^)(BOOL success, NSError * _Nullable error))completion
    NS_SWIFT_NAME(requestAuthorization(store:readTypes:completion:));
@end
NS_ASSUME_NONNULL_END
